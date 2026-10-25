#!/usr/bin/env bash

usage="USAGE: $0 <source_file> <target_dir>"

# 0 -- Parse Args
if [ $# -ne 2 ]; then
	echo $usage
	exit 1
fi

### Codec | Quality Settings ###
# 1080p h264 cq 20 ~ 14Mbps 
# 1080p h264 cq 18 ~ 17Mbps *
# 1080p hevc cq 24 ~ 12Mbps 
# 1080p hevc cq 20 ~ 17Mbps *
# 1080p hevc cq 18 ~ 23.5Mbps (visually "lossless")
# 1080p av1  cq 32 ~ 12.1Mbps
# 1080p av1  cq 24 ~ 19.7Mbps *
# 1080p av1  cq 22 ~ 24.9Mbps (visually "lossless")
# 1080p av1  cq 18 ~ 28.6Mbps
#ffmpeg -init_hw_device cuda=gpu -filter_hw_device gpu -canvas_size $canvas -i "$source_file" -map 0:v:0 -vf "$filters,hwupload" -map 0:a -c:a copy -map 0:a:0 -c:a:$((astreams)) aac -ac 3 -metadata:s:a:$((astreams)) title="Surround 2.1" -map 0:s? $profile -c:v:0 $vcodec -rc vbr -cq $qp -b:v 0 -maxrate 80M -bufsize 120M -c:s copy -cues_to_front true "$out_file"
#hwaccel='-init_hw_device cuda=gpu -filter_hw_device gpu'
#quality='-rc vbr -b:v 0 -maxrate 80M -bufsize 120M -preset p7 -cq 24'
#vcodec="h264_nvenc" # h264_nvenc hevc_nvenc av1_nvenc
hwaccel=''
profile='-profile:v high'
quality='-level:v 4.1 -preset slow -crf 18'
vcodec="libx264" # h264_nvenc hevc_nvenc av1_nvenc


source_file=$1
target_dir=$2
filters=

if [ ! -f "$source_file" ]; then
	echo $usage
	echo "$1 must be a regular file"
	exit 1
fi
if [ ! -d "$target_dir" ]; then
	echo $usage
	echo "$2 must be a directory"
	exit 2
fi

# 1 -- Crop Detection
echo "--- Performing Crop Detection ---"
maxtime=$(ffprobe "$source_file" 2>&1 | perl -ne 'print "$1\n" if /end (\d+)/' | tail -1)
if [ -z "$maxtime" ]; then
	echo "No chapters found"
	echo "Attempting Time Parse"
	duration=$(ffprobe "$source_file" 2>&1 | perl -ne 'print $1*3600+$2*60+$3,"\n" if /DURATION.*:.*(\d\d):(\d\d):(\d\d)\..*/' | tail -1)
	maxtime=$duration
fi 
echo "maxtime: $maxtime"
step=$((maxtime / 20))
if [ $step -eq 0 ]; then step=20; fi
echo "step: $step"

i=0
while [ $i -lt $maxtime ]; do
	printf '%d ' $i
	crops[$i]=$(ffmpeg -ss $i -t 1 -i "$source_file" -vf cropdetect -f null - 2>&1 | grep -o "crop=.*" | tail -1)
	printf '%s\n' ${crops[$i]}
	i=$((i+step))
done
echo
printf '%s\n' ${crops[*]} | sort | uniq -c | sort -n
crop=$(printf '%s\n' ${crops[*]} | sort | uniq -c | sort -n | tail -1)
crop=`expr match "$crop" '.*\(crop.*\)'`
echo "Using $crop"
canvas=`expr match "$crop" 'crop=\(.*\):.*:'`
echo "Canvas $canvas"
filters="$crop"

# 2 -- Video Format Detection
echo "--- Checking Video Format ---"
# Send ffprobe stream output to variables
source <(ffprobe -v quiet -select_streams v -show_entries stream -of flat=s=_ "$source_file")
# Detect interlaced video
if [ ${#streams_stream_0_field_order} -eq 2 ]; then
	echo "Found Interlaced: $streams_stream_0_field_order"
	filters="yadif=1:-1:0,$crop"
fi
# Detect HDR10 content
if [ "$streams_stream_0_profile" == 'Main 10' ]; then
	echo "Found 10-bit"
	# check for compatible features
	# ffmpeg -h encoder=hevc_nvenc
	#filters="$crop,format=p010le"
	filters="$crop,format=yuv420p10le"
	profile='-profile:v main10 -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc'
	#vcodec='hevc_nvenc' #Disabled due to HW lacking b-frame support
	hwaccel=''
	vcodec='libx265'
	quality='-rc vbr -b:v 0 -maxrate 80M -bufsize 120M -cq 20'
fi

# 3 -- Audio stream count to add AAC Track
astreams=$(ffprobe -v quiet -show_entries stream=index -select_streams a -of flat "$source_file" | wc -l )

# 4 -- Encode
echo "--- Performing Encode ---"
bname=$(basename "$source_file")
out_file="$target_dir/${bname}_$(date +%s).mkv"
set -x
#ffmpeg -hwaccel cuda -hwaccel_output_format cuda -canvas_size $canvas -i "$source_file" -map 0:v:0  -vf "$filters" -map 0:a -c:a copy -map 0:a:0 -c:a:$((astreams)) aac -ac 3 -metadata:s:a:$((astreams)) title="Surround 2.1" -map 0:s? -c:v:0 $vcodec -qp $qp -c:s copy "$out_file"
#ffmpeg -init_hw_device cuda=gpu -filter_hw_device gpu -canvas_size $canvas -i "$source_file" -map 0:v:0 -vf "$filters,hwupload" -map 0:a -c:a copy -map 0:a:0 -c:a:$((astreams)) aac -ac 3 -metadata:s:a:$((astreams)) title="Surround 2.1" -map 0:s? $profile -c:v:0 $vcodec -rc vbr -cq $qp -b:v 0 -maxrate 80M -bufsize 120M -c:s copy -cues_to_front true "$out_file"

ffmpeg $hwaccel -canvas_size $canvas -i "$source_file" -map 0:v:0 -vf "$filters" -map 0:a -c:a copy -map 0:a:0 -c:a:$((astreams)) aac -ac 2 -b:a:$((astreams)) 192k -metadata:s:a:$((astreams)) title="Stereo Fallback" $profile -c:v:0 $vcodec $quality -fps_mode cfr -force_key_frames 'expr:gte(t,n_forced*2)' "$out_file"
mkvmerge -o "${out_file}_subs" "$out_file" --no-video --no-audio "$source_file"
rm "$out_file"
mv "${out_file}_subs" "$out_file"
