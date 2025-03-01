# Ben's Ultimate FFmpeg Bash Script

## Design Goals
I wanted something that I could just point at a MakeMKV output folder and let it run. I wanted it to be easy to use, automatable, and accounted for a number of edge cases. 

## Prerequisites
- Bash
- nVidia GPU Drivers (can modify ffmpeg line for anything though)
- ffmpeg and ffprobe

## Usage
```bash
# encode single video, output to current folder
./encode.sh rips/bluray/movie.mkv .

# encode entire folder, output to target folder
for f in rips/bluray/* ; do
  ./encode.sh "$f" ./encoded/
done;

# encode entire "rips" folder, output to target folders
for d in "rips/*" ; do
  tdir=encoded/$(basename "$d")
  mkdir -p "$tdir"
  for f in "$d/*.mkv" ; do
    ./encoded.sh "$f" "$tdir"
  done
done

# check for encoders
ffmpeg -encoders | grep h264
```

## Features
- Crop using several video samples throughout the source
- Apply yadif ONLY if the source is interlaced
- Copy all subtitle tracks
- Dynamically add a 2.1 AAC audio track for Plex Web (newer plex web seems to hava a way to handle AC3 now)
- Leverage hardware acceleration
- Allow full tuning of the quality and codecs

## Motivations
I had issues with cropping on films like Tron, because the aspect ratio changes mid film. The autocrop will handle this by choosing the predominate (most common) aspect ratio.

I have plenty of older DVD soruces that are interlaced. By parsing the metadata, yadif can be applied dynamically, and only when neccessary.

I discovered issues with plex playback on web clients that didn't support AC3 (Chrome Browswers)\
https://cconcolato.github.io/media-mime-support/#video/mp4;%20codecs=%22ac-3%22 \
Plex seems capable of downmixing the audio properly, but having the 2.1 track avoids audio transcode.

Having subtitles is nice. I wanted to copy the PGS subs but noticed the placement could get wonky. The `canvas_size` parameter is an attempt to fix this. A good test case is Black Panther, because there are forced subs within the first 5 minutes where they speak Wakandan.

I really wanted to speed up encoding with an nVidia GPU.

## Useful Resources
Check Browser for supported codecs:\
https://cconcolato.github.io/media-mime-support/

Thorough Codec Comparison using VMAF and other evaluations:\
https://goughlui.com/2023/12/24/video-codec-round-up-2023-part-0-motivation-methodology-limitations/
