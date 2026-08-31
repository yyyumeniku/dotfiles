#!/usr/bin/env bash
# KDE-Spectacle-style screenshots:
#   Print       -> drag to select a region, saved to ~/Desktop with a notification
#   Shift+Print -> full screen
set -euo pipefail

out_dir="$HOME/Desktop"
file="$out_dir/screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png"

if [ "${1:-}" = "--full" ]; then
    grim "$file"
else
    area="$(slurp)" || exit 1
    grim -g "$area" "$file"
fi

notify-send -a Screenshot -i "$file" 'Screenshot saved' "$file"
