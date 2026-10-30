#!/bin/zsh
# Renders the Clausa ad to docs/app-store/video/clausa-ad.mp4: 29.6 s, 1080×1920,
# 30 fps, with its score. Everything is generated here — the music is synthesised
# (synth.py, arrange.py), the motion graphics are drawn frame by frame (film/),
# and the phone shows the real app's sample data in eight languages.
# Needs a booted simulator with a Debug build installed, ffmpeg, and python3 with numpy.
set -euo pipefail
here=${0:A:h}
root=${here:h:h:h}
work=$(mktemp -d)
mkdir -p $work/shots

xcrun simctl status_bar booted override --time 9:41 --batteryLevel 100 --batteryState charged --cellularBars 4 --wifiBars 3
for lang in en fr es de he ar ja th; do
  xcrun simctl terminate booted com.covera.app 2>/dev/null || true
  xcrun simctl launch booted com.covera.app -CoveraDemo -CoveraShot home -covera.onboardingSeen YES -covera.language $lang >/dev/null
  sleep 3.5   # let the entrance animations finish
  xcrun simctl io booted screenshot $work/shots/$lang.png >/dev/null
done
xcrun simctl terminate booted com.covera.app || true

python3 $here/arrange.py $work/score.wav
swiftc -O $here/film/*.swift -o $work/film
$work/film $work/shots | ffmpeg -v error -y -f rawvideo -pix_fmt bgra -s 1080x1920 -r 30 -i - -i $work/score.wav \
  -map 0:v -map 1:a -vf "format=yuv420p,noise=alls=1:allf=u" -c:v libx264 -preset slow -crf 17 -profile:v high \
  -c:a aac -b:a 256k -shortest -movflags +faststart $root/docs/app-store/video/clausa-ad.mp4
echo "wrote docs/app-store/video/clausa-ad.mp4"

# The narrated cut, ~40 s: Arthur's narration (narration.mp3, ElevenLabs via
# Higgsfield) over a calm bed that ducks under the voice. Each scene is stretched
# to its line (CLAUSA_NARRATED=1 in film/main.swift, the same map in
# arrange_vo.py), then the mix is normalised to -14 LUFS in two passes.
python3 $here/arrange_vo.py $here/narration.mp3 $work/vo.wav
read I TP LRA TH OFF < <(ffmpeg -hide_banner -i $work/vo.wav -af loudnorm=I=-14:TP=-1.0:LRA=11:print_format=json -f null - 2>&1 \
  | python3 -c "import sys,json; t=sys.stdin.read(); d=json.loads(t[t.rindex('{'):t.rindex('}')+1]); print(d['input_i'],d['input_tp'],d['input_lra'],d['input_thresh'],d['target_offset'])")
ffmpeg -v error -y -i $work/vo.wav -af "loudnorm=I=-14:TP=-1.0:LRA=11:measured_I=${I}:measured_TP=${TP}:measured_LRA=${LRA}:measured_thresh=${TH}:offset=${OFF}:linear=true" -ar 48000 $work/vo_n.wav
CLAUSA_NARRATED=1 $work/film $work/shots | ffmpeg -v error -y -f rawvideo -pix_fmt bgra -s 1080x1920 -r 30 -i - -i $work/vo_n.wav \
  -map 0:v -map 1:a -vf "format=yuv420p,noise=alls=1:allf=u" -c:v libx264 -preset slow -crf 17 -profile:v high \
  -c:a aac -b:a 256k -shortest -movflags +faststart $root/docs/app-store/video/clausa-ad-narrated.mp4
echo "wrote docs/app-store/video/clausa-ad-narrated.mp4"
