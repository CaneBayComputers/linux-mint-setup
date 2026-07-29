#!/usr/bin/env bash
set -euo pipefail

# Personal Linux dev machine setup
#
# Usage:
#   bash setup.sh [-y|--yes]
#
# Options:
#   -y, --yes   Answer yes to all optional prompts (unattended install)
#
# Notes: Requires apt-based distro (tested on Ubuntu/Mint)

log() { echo -e "\n==> $*"; }

ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) sed -n '3,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
  esac
done

# Ask a yes/no question. Defaults to YES on a bare Enter.
# Reads from /dev/tty so this still works when piped (curl ... | bash).
confirm() {
  local prompt="$1" reply
  if (( ASSUME_YES )); then
    echo "  ?? $prompt [Y/n] y (--yes)"
    return 0
  fi
  if [[ ! -r /dev/tty ]]; then
    echo "  !! No terminal available; assuming yes: $prompt"
    return 0
  fi
  read -r -p "  ?? $prompt [Y/n] " reply < /dev/tty || reply=""
  [[ ! "$reply" =~ ^[Nn] ]]
}

# ---------------- Ask everything up front, then run unattended ----------------
log "Setup options"

REMOVE_LIBREOFFICE=0
confirm "Remove LibreOffice Writer/Impress/Draw/Math/Base? (Calc is kept)" && REMOVE_LIBREOFFICE=1

DISABLE_BLUETOOTH=0
confirm "Disable Bluetooth? (bluetooth + blueman-mechanism services)" && DISABLE_BLUETOOTH=1

# ---------------- System cleanup (from remove_software.sh) ----------------
log "Purging unwanted packages..."
PKGS=(
  "firefox*"
  gufw
  celluloid
  hexchat
  hypnotix
  "redshift*"
  rhythmbox
  "thunderbird*"
  warpinator
  webapp-manager
  mintbackup
  bulky
  mintwelcome
  onboard
  simple-scan
  drawing
  gnome-calendar
  thingy
  sticky
  redshift
  timeshift
  ufw
  openvpn
  cmatrix
  cmatrix-xfont
  brltty          # braille driver; hijacks CH340 USB-serial (Arduino) ports on Linux
)
for PKG in "${PKGS[@]}"; do
  echo "  -> Removing $PKG"
  sudo apt-get -y -q purge "$PKG" || true
done

# Remove all LibreOffice apps EXCEPT Calc. Calc and its shared deps
# (libreoffice-core/-common, base-core, gtk3, etc.) are kept; the orphaned
# uiconfig/help packages for the removed apps get swept by autoremove below.
if (( REMOVE_LIBREOFFICE )); then
  log "Removing LibreOffice apps (keeping Calc only)..."
  LIBRE_REMOVE=(
    libreoffice-writer
    libreoffice-impress
    libreoffice-draw
    libreoffice-math
    libreoffice-base
  )
  for PKG in "${LIBRE_REMOVE[@]}"; do
    echo "  -> Removing $PKG"
    sudo apt-get -y -q purge "$PKG" || true
  done
else
  log "Keeping LibreOffice (skipped by request)."
fi

log "Disabling unneeded services and timers (if present)..."
SERVICES=(
  avahi-daemon
  ModemManager
  accounts-daemon
  anacron
  kerneloops
  motd-news
  networkd-dispatcher
  plocate-updatedb
  rsyslog
  secureboot-db
  touchegg
  switcheroo-control
)
if (( DISABLE_BLUETOOTH )); then
  SERVICES+=(bluetooth blueman-mechanism)
else
  echo "  -> Leaving Bluetooth enabled (skipped by request)"
fi
for SVC in "${SERVICES[@]}"; do
  echo "  -> Checking $SVC.service and $SVC.timer"
  if systemctl list-unit-files | grep -q "^$SVC.service"; then
    echo "     Disabling $SVC.service"
    sudo systemctl disable --now "$SVC.service" || true
  fi
  if systemctl list-unit-files | grep -q "^$SVC.timer"; then
    echo "     Disabling $SVC.timer"
    sudo systemctl disable --now "$SVC.timer" || true
  fi
done

# Extra: Stop legacy service if still running
echo "==> Stopping legacy avahi-daemon (if running)..."
sudo service avahi-daemon stop || true

# Disable Cinnamon's built-in "Night Light" blue light filter.
# It can't be uninstalled (it's part of the core 'cinnamon' package), so we
# just turn the feature off. Runs as the invoking user, not root.
log "Disabling Cinnamon Night Light (blue light filter)..."
gsettings set org.cinnamon.settings-daemon.plugins.color night-light-enabled false 2>/dev/null \
  || echo "  !! Could not set gsettings (no session bus / not Cinnamon?); skipping"

log "Final cleanup..."
sudo apt-get autoremove -y -q || true
sudo apt-get autoclean -y -q || true
