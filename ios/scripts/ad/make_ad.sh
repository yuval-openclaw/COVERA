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
