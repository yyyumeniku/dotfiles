#!/bin/bash
shopt -s nullglob

icons=$(awk -f ~/.config/sway/window-icons.awk \
    /usr/share/applications/*.desktop \
    /usr/local/share/applications/*.desktop \
    /var/lib/flatpak/exports/share/applications/*.desktop \
    "$HOME"/.local/share/applications/*.desktop)

swaymsg -t get_tree |
    jq -r --argjson icons "$icons" '
        .. | objects |
        select(.type == "con") |
        select(.app_id != null or .window_properties.class != null) |
        (.app_id // .window_properties.class) as $app |
        "\(.id)\t\($app)\t\(.name // "")\u0000icon\u001f\($icons[$app] // $app)"' |
    fuzzel --dmenu --prompt=": " --with-nth='{3}' |
    cut -f1 |
    while read -r id; do
        [ -n "$id" ] && swaymsg "[con_id=$id]" focus
    done
