#!/usr/bin/env bash

usage="USAGE: $0 <source_file> <target_dir>"

# 0 -- Parse Args
if [ $# -ne 2 ]; then
	echo $usage
	exit 1
fi

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
step=$((maxtime / 20))

i=0
while [ $i -lt $maxtime ]; do
	printf '%d ' $i
	crops[$i]=$(ffmpeg -ss $i -t 1 -i "$source_file" -vf cropdetect -f null - 2>&1 | grep -o "crop=.*" | tail -1)
	i=$((i+step))
done
echo
printf '%s\n' ${crops[*]} | sort | uniq -c | sort -n
crop=$(printf '%s\n' ${crops[*]} | sort | uniq -c | sort -n | tail -1)
crop=`expr match "$crop" '.*\(crop.*\)'`
echo "Using $crop"
canvas=`expr match "crop=1920:800:0:140" 'crop=\(.*\):.*:'`
echo "Canvas $canvas"
filters=$crop

# 2 -- Interlace Detection
echo "--- Checking Interlaced ---"
#ffprobe "$source_file" 2>&1 | grep -q progressive
(
source <(ffprobe -v quiet -select_streams v -show_entries stream=field_order -of flat=s=_ "$source_file")
if [ ${#streams_stream_0_field_order} -eq 2 ]; then
	echo "Found Interlaced: $streams_stream_0_field_order"
	filters="yadif=1:-1:0,$crop"
fi
)

# 3 -- Audio stream count to add AAC Track
astreams=$(ffprobe -v quiet -show_entries stream=index -select_streams a -of flat "$source_file" | wc -l )

# 4 -- Encode
echo "--- Performing Encode ---"
bname=$(basename "$source_file")
out_file="$target_dir/${bname}_$(date +%s).mkv"
# 1080p h264 qp 20 ~ 14Mbps
# 1080p h264 qp 18 ~ 17Mbps *
# 1080p hevc qp 24 ~ 12Mbps
# 1080p hevc qp 20 ~ 17Mbps *
# 1080p hevc qp 18 ~ 23.5Mbps (visually "lossless")
# 1080p av1  qp 32 ~ 12.1Mbps
# 1080p av1  qp 24 ~ 19.7Mbps *
# 1080p av1  qp 22 ~ 24.9Mbps (visually "lossless")
# 1080p av1  qp 18 ~ 28.6Mbps
qp=18
vcodec="h264_nvenc" # h264_nvenc hevc_nvenc av1_nvenc
set -x
ffmpeg -hwaccel cuda -hwaccel_output_format cuda -canvas_size "$canvas" -i "$source_file" -map 0:v:0  -vf "$filters" -map 0:a -c:a copy -map 0:a:0 -c:a:$((astreams)) aac -ac 3 -metadata:s:a:$((astreams)) title="Surround 2.1" -map 0:s? -c:v:0 $vcodec -qp $qp -c:s copy "$out_file"

