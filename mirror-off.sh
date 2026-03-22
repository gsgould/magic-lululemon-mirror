#!/bin/bash
# mirror-off.sh — Turn off the mirror display via CEC
cec-ctl -d 1 --playback --to 0 --standby 2>/dev/null
echo "Mirror display off"
