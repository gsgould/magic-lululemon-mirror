#!/bin/bash
# mirror-on.sh — Turn on the mirror display via CEC
cec-ctl -d 1 --playback --to 0 --image-view-on 2>/dev/null
echo "Mirror display on"
