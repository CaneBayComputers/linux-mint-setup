#!/usr/bin/env bash
set -euo pipefail

# Personal Linux dev machine setup
#
# Notes: Requires apt-based distro (tested on Ubuntu/Mint)

log() { echo -e "\n==> $*"; }

usage() {
  cat <<'USAGE'
Usage: bash setup.sh [options]

Options:
  -y, --yes               Answer yes to any prompt not already set by a flag
      --keep-libreoffice  Keep LibreOffice (no prompt)
      --remove-libreoffice
                          Remove LibreOffice except Calc (no prompt)
      --keep-bluetooth    Leave Bluetooth enabled (no prompt)
      --disable-bluetooth Disable Bluetooth (no prompt)
  -h, --help              Show this help

Flags win over --yes and suppress the matching prompt, which makes remote
and unattended runs deterministic. With no flags and no terminal, prompts
default to yes.
USAGE
}

ASSUME_YES=0
OPT_LIBREOFFICE=""   # "" = ask, 0 = keep, 1 = remove
OPT_BLUETOOTH=""     # "" = ask, 0 = keep, 1 = disable
for arg in "$@"; do
  case "$arg" in
    -y|--yes)              ASSUME_YES=1 ;;
    --keep-libreoffice)    OPT_LIBREOFFICE=0 ;;
    --remove-libreoffice)  OPT_LIBREOFFICE=1 ;;
    --keep-bluetooth)      OPT_BLUETOOTH=0 ;;
    --disable-bluetooth)   OPT_BLUETOOTH=1 ;;
    -h|--help)             usage; exit 0 ;;
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

# decide <preset> <question>: honour an explicit flag if given, else prompt.
decide() {
  local preset="$1" question="$2"
  if [[ "$preset" == "1" ]]; then
    echo "  ?? $question -> yes (flag)"
    return 0
  elif [[ "$preset" == "0" ]]; then
    echo "  ?? $question -> no (flag)"
    return 1
  fi
  confirm "$question"
}

# ---------------- Ask everything up front, then run unattended ----------------
log "Setup options"

REMOVE_LIBREOFFICE=0
decide "$OPT_LIBREOFFICE" "Remove LibreOffice Writer/Impress/Draw/Math/Base? (Calc is kept)" && REMOVE_LIBREOFFICE=1

DISABLE_BLUETOOTH=0
decide "$OPT_BLUETOOTH" "Disable Bluetooth? (bluetooth + blueman-mechanism services)" && DISABLE_BLUETOOTH=1

# ---------------- APT mirrors ----------------
# Point Main (Mint) and Base (Ubuntu) at fast mirrors. Codenames are read from
# /etc/os-release so this keeps working across Mint releases. The -security line
# is deliberately left on security.ubuntu.com -- that's what Mint's own Software
# Sources tool does, so security updates come straight from Canonical.
MINT_MIRROR="https://fastly.linuxmint.io"
BASE_MIRROR="http://mirror.nodesdirect.com/ubuntu"
REPO_LIST="/etc/apt/sources.list.d/official-package-repositories.list"

log "Setting APT mirrors..."
MINT_CODENAME="$(. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-}")"
UBUNTU_BASE="$(. /etc/os-release 2>/dev/null && echo "${UBUNTU_CODENAME:-}")"

if [[ -z "$MINT_CODENAME" || -z "$UBUNTU_BASE" ]]; then
  echo "  !! Could not detect Mint/Ubuntu codenames; leaving sources untouched"
else
  echo "  -> Mint '$MINT_CODENAME' -> $MINT_MIRROR"
  echo "  -> Base '$UBUNTU_BASE' -> $BASE_MIRROR"
  if [[ -f "$REPO_LIST" ]]; then
    BACKUP="$REPO_LIST.bak-$(date +%Y%m%d%H%M%S)"
    sudo cp "$REPO_LIST" "$BACKUP"
    echo "  -> Backed up existing list to $BACKUP"
  fi
  sudo tee "$REPO_LIST" >/dev/null <<EOF
deb $MINT_MIRROR $MINT_CODENAME main upstream import backport

deb $BASE_MIRROR $UBUNTU_BASE main restricted universe multiverse
deb $BASE_MIRROR $UBUNTU_BASE-updates main restricted universe multiverse
deb $BASE_MIRROR $UBUNTU_BASE-backports main restricted universe multiverse

deb http://security.ubuntu.com/ubuntu/ $UBUNTU_BASE-security main restricted universe multiverse
EOF
  log "Refreshing package lists..."
  sudo apt-get update -q || echo "  !! apt-get update reported errors; continuing"
fi

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
  rhythmbox-data  # orphaned by the rhythmbox purge; autoremove misses it
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

# ---------------- Update Manager automation ----------------
# Mirrors Update Manager -> Preferences -> Automation:
#   upgrade    = "Apply updates automatically"
#   autoremove = "Remove obsolete kernels and dependencies"
# Enabling 'upgrade' also installs the update blacklist, per mintupdate-automation.
# Done last so the automation timers can't fire while we still hold the dpkg lock.
log "Configuring Update Manager automation..."
if ! command -v mintupdate-automation >/dev/null 2>&1; then
  echo "  !! mintupdate-automation not found (not Linux Mint?); skipping"
else
  for AUTOMATION in upgrade autoremove; do
    echo "  -> Enabling '$AUTOMATION'"
    sudo mintupdate-automation "$AUTOMATION" enable || echo "     !! Failed to enable $AUTOMATION"
  done
  for FLAG in mintupdate-automatic-upgrades-enabled mintupdate-automatic-removals-enabled; do
    if [[ -e "/var/lib/linuxmint/$FLAG" ]]; then
      echo "     [ok] $FLAG"
    else
      echo "     !! $FLAG missing -- automation may not be active"
    fi
  done
fi
