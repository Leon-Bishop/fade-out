#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
clang -std=c11 -Wall -Wextra -Werror -I Sources/FadeOutDSP/include \
  Sources/FadeOutDSP/FadeOutDSP.c Tests/layout_smoke.c \
  -framework CoreAudio -o /tmp/fadeout-layout-smoke
/tmp/fadeout-layout-smoke
