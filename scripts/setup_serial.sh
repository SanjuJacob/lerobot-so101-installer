#!/usr/bin/env bash
# Give the current user permanent access to the SO-101 USB motor boards
# (Waveshare / Feetech boards use WCH CH343/CH340 chips, USB vendor 1a86).
#
# Replaces the doc's "sudo chmod 666 /dev/ttyACM0" which is lost on every replug.
set -euo pipefail

ASSUME_YES="${ASSUME_YES:-0}"
RULES_FILE=/etc/udev/rules.d/99-so101-serial.rules

confirm() {
    [[ "$ASSUME_YES" -eq 1 ]] && return 0
    [[ -t 0 ]] || return 0
    read -r -p "$1 [Y/n] " ans
    [[ -z "$ans" || "$ans" =~ ^[Yy] ]]
}

# 1. dialout group (standard owner group of /dev/ttyACM* and /dev/ttyUSB*)
if id -nG "$USER" | tr ' ' '\n' | grep -qx dialout; then
    echo "[ok] $USER is already in the 'dialout' group"
else
    sudo usermod -aG dialout "$USER"
    echo "[ok] Added $USER to 'dialout' (takes effect after logging out and back in)"
fi

# 2. udev rule: world-read/write for WCH serial chips + keep ModemManager away
sudo tee "$RULES_FILE" >/dev/null <<'EOF'
# SO-100 / SO-101 bus servo adapters (WCH CH343 = 1a86:55d3, CH340 = 1a86:7523, CH9102 = 1a86:55d4)
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", MODE="0666", ENV{ID_MM_DEVICE_IGNORE}="1"
EOF
echo "[ok] Wrote $RULES_FILE"

# 3. brltty (braille driver) on Ubuntu grabs CH340 adapters and makes them vanish
if dpkg -s brltty >/dev/null 2>&1; then
    echo "[info] 'brltty' (braille display service) is installed. It is known to steal"
    echo "       CH340 USB-serial adapters, so the robot port disappears right after plug-in."
    if confirm "Remove brltty? (only needed for braille displays)"; then
        sudo apt-get remove -y brltty
    fi
fi

sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=tty
echo "[ok] udev rules reloaded - unplug and replug the arms if they were connected"
