#!/usr/bin/env bash
# volume.sh up|down|mute|mic — change volume/mute and show a dunst notification
set -euo pipefail

case "${1:-}" in
  up)   pactl set-sink-volume @DEFAULT_SINK@ +5% ;;
  down) pactl set-sink-volume @DEFAULT_SINK@ -5% ;;
  mute) pactl set-sink-mute @DEFAULT_SINK@ toggle ;;
  mic)
    pactl set-source-mute @DEFAULT_SOURCE@ toggle
    if pactl get-source-mute @DEFAULT_SOURCE@ | grep -q 'yes'; then
      notify-send -r 9002 -a Volume -h string:x-dunst-stack-tag:volume 'Microphone' 'Muted'
    else
      notify-send -r 9002 -a Volume -h string:x-dunst-stack-tag:volume 'Microphone' 'Unmuted'
    fi
    exit 0
    ;;
  *) exit 1 ;;
esac

vol=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -oP '\d+(?=%)' | head -1)
vol=${vol:-0}

if pactl get-sink-mute @DEFAULT_SINK@ | grep -q 'yes'; then
  notify-send -r 9001 -a Volume -h string:x-dunst-stack-tag:volume 'Volume' 'Muted'
else
  notify-send -r 9001 -a Volume -h string:x-dunst-stack-tag:volume -h int:value:"$vol" 'Volume' "${vol}%"
fi
