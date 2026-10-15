#!/usr/bin/env bash
# Remove everything install.sh created inside this folder (venv, LeRobot clone,
# CLI link). System packages, uv, recorded datasets and calibration files in
# ~/.cache/huggingface are kept. Pass --udev to also delete the udev rules.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "This removes: $REPO_DIR/.venv, $REPO_DIR/lerobot, ~/.local/bin/so101"
read -r -p "Continue? [y/N] " ans
[[ "$ans" =~ ^[Yy] ]] || exit 0

rm -rf "$REPO_DIR/.venv" "$REPO_DIR/lerobot"
[[ -L "$HOME/.local/bin/so101" ]] && rm "$HOME/.local/bin/so101"

if [[ "${1:-}" == "--udev" ]]; then
    sudo rm -f /etc/udev/rules.d/99-so101-serial.rules /etc/udev/rules.d/99-so101-names.rules
    sudo udevadm control --reload-rules
fi
echo "Done. config/so101.env and outputs/ were kept."
