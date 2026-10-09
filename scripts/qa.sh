#!/bin/zsh
# Drives the running SAVISUL into a state for screenshots: ./scripts/qa.sh island.expand.home [shot-name x,y,w,h]
# SAVISUL listens only when launched with --qa: quit it, then run `open -a SAVISUL --args --qa`.
command="$1"
osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('com.savisul.qa', '$command', \$(), true)" >/dev/null
if [[ -n "${2:-}" ]]; then
  sleep "${QA_WAIT:-1.2}"
  mkdir -p "$(dirname "$0")/../.build/shots"
  screencapture -x -R "${3:-396,0,720,300}" "$(dirname "$0")/../.build/shots/$2.png"
  echo "$(cd "$(dirname "$0")/.." && pwd)/.build/shots/$2.png"
fi
