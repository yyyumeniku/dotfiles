BEGIN { printf "{" }
FILENAME != prevfile {
    if (prevfile != "") flush()
    prevfile = FILENAME
    nwm = 0
    in_entry = 0
    name = ""; exec = ""; icon = ""
}
{
    if ($0 ~ /^\[Desktop Entry\]/) { in_entry = 1; next }
    if ($0 ~ /^\[/) { in_entry = 0; next }
    if (!in_entry) next
    if ($0 ~ /^Name=/ && name == "") name = substr($0, 6)
    if ($0 ~ /^Exec=/ && exec == "") exec = substr($0, 6)
    if ($0 ~ /^Icon=/ && icon == "") icon = substr($0, 6)
    if ($0 ~ /^StartupWMClass=/) { wmclasses[nwm++] = substr($0, 16) }
}
END { flush(); printf "}\n" }

function add(key, icon,   esc) {
    if (key == "" || icon == "") return
    if (key in seen) return
    seen[key] = 1
    esc = key
    gsub(/"/, "\\\"", esc)
    printf "%s\"%s\":\"%s\"", (n++ ? "," : ""), esc, icon
}
function flush() {
    if (icon == "") return
    exe = exec
    gsub(/"/, "", exe)
    split(exe, a, /[[:space:]]+/)
    cmd = a[1]
    gsub(/.*\//, "", cmd)
    add(cmd, icon)
    add(name, icon)
    for (i = 0; i < nwm; i++) add(wmclasses[i], icon)
    base = prevfile
    gsub(/.*\//, "", base)
    sub(/\.desktop$/, "", base)
    add(base, icon)
}
