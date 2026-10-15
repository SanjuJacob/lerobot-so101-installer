# Activate the LeRobot virtual environment in the current shell:
#   source activate.sh
# Afterwards all lerobot-* commands (lerobot-find-port, lerobot-calibrate, ...) work.
# Type 'deactivate' to leave the environment.
_lerobot_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ ! -f "$_lerobot_dir/.venv/bin/activate" ]; then
    echo "No venv at $_lerobot_dir/.venv - run ./install.sh first." >&2
else
    # shellcheck disable=SC1091
    . "$_lerobot_dir/.venv/bin/activate"
    echo "LeRobot venv active ($(python --version)). Type 'deactivate' to leave."
fi
unset _lerobot_dir
