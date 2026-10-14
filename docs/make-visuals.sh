#!/bin/zsh
# Repaints the README pictures in docs/ from the app's own drawing code. The GIF needs ffmpeg.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
.build/release/Mochi --showcase docs
.build/release/Mochi --icon docs/icon-1024.png
sips -z 256 256 docs/icon-1024.png --out docs/icon.png >/dev/null
rm docs/icon-1024.png
ffmpeg -loglevel error -y -framerate 25 -i docs/frames/%03d.png \
  -vf "split[a][b];[a]palettegen=max_colors=256:stats_mode=diff[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
  -loop 0 docs/demo.gif
rm -rf docs/frames
echo "Updated docs/"
