#!/usr/bin/env bash
#
# debian-minimal-setup.sh
#
# Switches Debian to unstable (sid), installs nala/ly/firefox/micro/fuzzel/
# fastfetch/ufw/git, debloats unneeded services, and tunes RAM/CPU usage.
#
# Written for a headless SSH box (dual Xeon E5-2690 v4 + GTX 1050 Ti).
# No script can be 100% guaranteed on a distro switch to sid — package
# conflicts CAN require manual intervention. This script is written to
# fail loudly and stop (set -e) rather than silently break your SSH access.
#
# USAGE:
#   sudo tmux new -s setup          # run inside tmux, not raw ssh
#   sudo bash debian-minimal-setup.sh
#
set -euo pipefail
trap 's=$?; echo -e "\n\033[1;31m[FAILED] line $LINENO, exit $s. Fix the error above and re-run — the script is safe to re-run.\033[0m"; exit $s' ERR

log() { echo -e "\n\033[1;32m==> $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }

# ── 0. Sanity checks ─────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo -i, then run this script)."; exit 1; }

if [[ -z "${TMUX:-}" && -z "${STY:-}" ]]; then
  warn "You're not inside tmux/screen. If your SSH session drops mid-upgrade,"
  warn "this script stops and you'll need to reconnect and re-run it."
  read -rp "Continue anyway? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted. Run: tmux new -s setup"; exit 1; }
fi

export DEBIAN_FRONTEND=noninteractive
APT_SAFE=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -y)

# ── 1. Protect SSH access before touching anything ─────────────────────
log "Protecting SSH from autoremove"
apt-mark manual openssh-server openssh-client openssh-sftp-server 2>/dev/null || true

BACKUP_DIR="/root/debian-minimal-setup-backup-$(date +%s)"
mkdir -p "$BACKUP_DIR"
cp -a /etc/apt/sources.list "$BACKUP_DIR/" 2>/dev/null || true
cp -a /etc/apt/sources.list.d "$BACKUP_DIR/" 2>/dev/null || true
log "Old apt config backed up to $BACKUP_DIR"

# ── 2. Switch to unstable (sid) ─────────────────────────────────────────
# Debian 12/13 default to the new deb822 format (/etc/apt/sources.list.d/debian.sources).
# Older systems use the classic one-line /etc/apt/sources.list. Handle both.
log "Switching apt sources to unstable (sid)"
DEB822_FILE="/etc/apt/sources.list.d/debian.sources"
LEGACY_FILE="/etc/apt/sources.list"

if [[ -f "$DEB822_FILE" ]]; then
  cat >"$DEB822_FILE" <<'EOF'
Types: deb deb-src
URIs: http://deb.debian.org/debian/
Suites: unstable
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
elif [[ -f "$LEGACY_FILE" ]]; then
  cat >"$LEGACY_FILE" <<'EOF'
deb http://deb.debian.org/debian/ unstable main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ unstable main contrib non-free non-free-firmware
EOF
else
  echo "No apt sources file found at all — can't continue." >&2
  exit 1
fi

# sid has no separate -security/-updates suites; neutralize leftovers so apt
# update doesn't 404 on them.
shopt -s nullglob
for f in /etc/apt/sources.list.d/*security* /etc/apt/sources.list.d/*updates*; do
  [[ "$f" == "$DEB822_FILE" ]] && continue
  mv "$f" "$f.disabled"
done
shopt -u nullglob

# ── 3. Stop recommends/suggests bloat before the first install ─────────
log "Disabling apt Recommends/Suggests"
cat >/etc/apt/apt.conf.d/99no-recommends <<'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF

# ── 4. Update + full-upgrade to sid ─────────────────────────────────────
log "apt update"
apt update

log "Full upgrade to sid — this WILL take a while, let it run"
apt "${APT_SAFE[@]}" full-upgrade

# ── 5. nala ───────────────────────────────────────────────────────────
log "Installing nala"
apt "${APT_SAFE[@]}" install nala

# ── 6. Requested packages + ly's build/runtime deps ─────────────────────
log "Installing firefox, micro, fuzzel, fastfetch, ufw, git + ly's deps"
nala install -y \
  firefox micro fuzzel fastfetch ufw git \
  build-essential libpam0g-dev libxcb-xkb-dev xauth xserver-xorg brightnessctl xinit \
  curl jq ca-certificates

# ── 7. Firewall — allow SSH BEFORE enabling, or you lock yourself out ──
log "Configuring ufw (allowing SSH first)"
ufw allow OpenSSH
ufw --force enable

# ── 8. zram swap (RAM-backed compressed swap, saves real RAM long-term) ─
log "Setting up zram swap"
apt "${APT_SAFE[@]}" install systemd-zram-generator
cat >/etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
EOF
systemctl daemon-reload

# ── 9. Trim journald ─────────────────────────────────────────────────────
log "Trimming journald log storage"
sed -i -E \
  -e 's/^#?Storage=.*/Storage=volatile/' \
  -e 's/^#?SystemMaxUse=.*/SystemMaxUse=50M/' \
  /etc/systemd/journald.conf
grep -q '^Storage=' /etc/systemd/journald.conf || echo 'Storage=volatile' >>/etc/systemd/journald.conf
grep -q '^SystemMaxUse=' /etc/systemd/journald.conf || echo 'SystemMaxUse=50M' >>/etc/systemd/journald.conf
systemctl restart systemd-journald

# ── 10. Debloat — purge common unneeded packages ────────────────────────
# Review this list before running if any of these are things you actually
# need (e.g. cups if you print, bluez if you use Bluetooth).
log "Purging unneeded packages (exim4, cups, avahi, modemmanager, bluez)"
apt "${APT_SAFE[@]}" purge \
  exim4 exim4-base exim4-config exim4-daemon-light \
  cups cups-common cups-daemon \
  avahi-daemon avahi-utils \
  modemmanager \
  bluez bluez-firmware 2>/dev/null || true

apt "${APT_SAFE[@]}" autoremove --purge
apt clean

# ── 11. zig (needed to build ly — not packaged in Debian) ──────────────
log "Fetching official zig toolchain (from ziglang.org, not a 3rd-party repo)"
ZIG_INDEX=$(curl -fsSL https://ziglang.org/download/index.json)
ZIG_URL=$(echo "$ZIG_INDEX" | jq -r '
  to_entries
  | map(select(.key != "master"))
  | sort_by(.key | split(".") | map(tonumber? // 0))
  | last
  | .value["x86_64-linux"].tarball
')
[[ "$ZIG_URL" != "null" && -n "$ZIG_URL" ]] || { echo "Couldn't resolve a zig download URL — grab it manually from https://ziglang.org/download"; exit 1; }

curl -fsSL -o /tmp/zig.tar.xz "$ZIG_URL"
rm -rf /opt/zig
mkdir -p /opt/zig
tar -xf /tmp/zig.tar.xz -C /opt/zig --strip-components=1
ln -sf /opt/zig/zig /usr/local/bin/zig
rm -f /tmp/zig.tar.xz
log "zig $(zig version) installed"

# ── 12. Build & install ly (not packaged in Debian) ─────────────────────
log "Building ly login manager"
LY_DIR=$(mktemp -d)
git clone --depth=1 https://github.com/fairyglade/ly.git "$LY_DIR"
(
  cd "$LY_DIR"
  zig build
  zig build installexe -Dinit_system=systemd
)
rm -rf "$LY_DIR"

log "Enabling ly on tty2, disabling getty on tty2"
systemctl enable ly@tty2.service
systemctl disable getty@tty2.service

# ── Done ──────────────────────────────────────────────────────────────
log "All done."
echo "  - Suites now: unstable (sid)"
echo "  - Package manager: nala (apt frontend, still apt/dpkg underneath)"
echo "  - Login manager: ly, will start on tty2 after reboot"
echo "  - Backups of your old apt sources: $BACKUP_DIR"
echo
free -h
echo
warn "Reboot when ready: systemctl reboot"
warn "First reboot after switching to sid — stay on this SSH session until"
warn "you've confirmed you can reconnect after the reboot."
