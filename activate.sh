# Source this file to activate the LeRobot venv in your current shell:
#   source activate.sh
# Afterwards all lerobot-* commands (lerobot-find-port, lerobot-calibrate, ...) work directly,
# and $FOLLOWER_PORT, $LEADER_PORT, $FOLLOWER_ID, ... from config/so101.env are set.
_so101_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ ! -f "$_so101_dir/.venv/bin/activate" ]; then
    echo "No venv at $_so101_dir/.venv - run ./install.sh first." >&2
else
    # shellcheck disable=SC1091
    . "$_so101_dir/.venv/bin/activate"
    if [ -f "$_so101_dir/config/so101.env" ]; then
        # not exported, so it never overrides the config file for the so101 wrapper
        . "$_so101_dir/config/so101.env"
    fi
    echo "LeRobot venv active ($(python --version)). Type 'deactivate' to leave."
fi
unset _so101_dir
