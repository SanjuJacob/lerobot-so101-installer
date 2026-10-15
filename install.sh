#!/usr/bin/env bash
# One-shot installer for LeRobot + SO-101 on Ubuntu 24.04 (tested target: RTX 5090).
#
# Everything Python-related goes into a project-local virtual environment
# (./.venv). The global/system Python is never modified.
#
# Usage:
#   ./install.sh                     # full install
#   ./install.sh --help              # all options
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- defaults (each can be overridden by env var or flag) -------------------
VENV_DIR="${VENV_DIR:-$REPO_DIR/.venv}"
LEROBOT_DIR="${LEROBOT_DIR:-$REPO_DIR/lerobot}"
LEROBOT_REPO="${LEROBOT_REPO:-https://github.com/huggingface/lerobot.git}"
LEROBOT_REF="${LEROBOT_REF:-main}"
LEROBOT_EXTRAS="${LEROBOT_EXTRAS:-feetech,core_scripts,training,smolvla}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
TORCH_BACKEND="${TORCH_BACKEND:-}"   # empty = LeRobot default (cu128). e.g. cu130
SKIP_APT=0
SKIP_SERIAL=0
SKIP_VERIFY=0
ASSUME_YES=0

usage() {
    cat <<EOF
Usage: ./install.sh [options]

Options:
  --extras LIST      LeRobot extras to install   (default: $LEROBOT_EXTRAS)
  --ref REF          LeRobot git branch/tag/sha  (default: $LEROBOT_REF)
  --torch BACKEND    Reinstall torch for a CUDA variant, e.g. cu128, cu130
                     (default: keep LeRobot's pinned cu128 build)
  --venv DIR         Virtual environment path    (default: ./.venv)
  --no-apt           Skip system packages (apt)
  --no-serial        Skip serial-port permissions / udev rules
  --no-verify        Skip the post-install environment check
  -y, --yes          Answer yes to all prompts
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --extras)    LEROBOT_EXTRAS="$2"; shift 2 ;;
        --ref)       LEROBOT_REF="$2"; shift 2 ;;
        --torch)     TORCH_BACKEND="$2"; shift 2 ;;
        --venv)      VENV_DIR="$2"; shift 2 ;;
        --no-apt)    SKIP_APT=1; shift ;;
        --no-serial) SKIP_SERIAL=1; shift ;;
        --no-verify) SKIP_VERIFY=1; shift ;;
        -y|--yes)    ASSUME_YES=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# ---- helpers -----------------------------------------------------------------
c_blue=$'\e[1;34m'; c_yel=$'\e[1;33m'; c_red=$'\e[1;31m'; c_grn=$'\e[1;32m'; c_off=$'\e[0m'
step() { echo; echo "${c_blue}==> $*${c_off}"; }
warn() { echo "${c_yel}[warn] $*${c_off}"; }
die()  { echo "${c_red}[error] $*${c_off}" >&2; exit 1; }
ok()   { echo "${c_grn}[ok] $*${c_off}"; }

# ---- 0. sanity checks --------------------------------------------------------
[[ $EUID -eq 0 ]] && die "Do not run this script as root / with sudo. It asks for sudo only when needed."
[[ "$(uname -s)" == "Linux" ]] || die "This installer targets Linux (Ubuntu 24.04)."

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
        warn "Detected ${PRETTY_NAME:-unknown OS}. This script was written for Ubuntu 24.04; continuing anyway."
    else
        ok "OS: $PRETTY_NAME, kernel $(uname -r)"
    fi
fi

# ---- 1. system packages (not Python) ----------------------------------------
if [[ $SKIP_APT -eq 0 ]]; then
    step "Installing system packages with apt (needs sudo)"
    # ffmpeg            -> video encode/decode (TorchCodec >= 0.10 links to system ffmpeg)
    # build tools/libav -> fallback for building wheels from source (PyAV, evdev)
    # v4l-utils         -> list/inspect USB cameras (v4l2-ctl)
    sudo apt-get update
    sudo apt-get install -y \
        git curl ca-certificates \
        ffmpeg \
        build-essential cmake pkg-config \
        libavformat-dev libavcodec-dev libavdevice-dev libavutil-dev \
        libswscale-dev libswresample-dev libavfilter-dev \
        libevdev-dev \
        v4l-utils
else
    step "Skipping apt packages (--no-apt)"
fi

# ---- 2. NVIDIA driver check (we never install drivers automatically) --------
step "Checking NVIDIA driver"
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)"
    drv="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)"
    ok "GPU: $gpu_name, driver $drv"
    drv_major="${drv%%.*}"
    if (( drv_major < 570 )); then
        warn "Driver $drv is too old for the CUDA 12.8 PyTorch wheels (need >= 570.86)."
        warn "RTX 50xx needs the *open* kernel module: sudo ubuntu-drivers install  (or nvidia-driver-580-open)"
    elif (( drv_major >= 580 )) && [[ -z "$TORCH_BACKEND" ]]; then
        ok "Driver supports CUDA 12.8 (default) and 13.x wheels; pass --torch cu130 to use CUDA 13.0 torch."
    fi
else
    warn "nvidia-smi not working: no NVIDIA driver loaded. PyTorch will run on CPU only."
    warn "See README.md -> 'NVIDIA driver' to install it, then re-run ./install.sh --no-apt"
fi

# ---- 3. uv (user-level tool in ~/.local/bin, does not touch system Python) --
step "Ensuring 'uv' is available"
export PATH="$HOME/.local/bin:$PATH"
if ! command -v uv >/dev/null 2>&1; then
    # UV_NO_MODIFY_PATH: do not edit ~/.bashrc / ~/.profile (Ubuntu already puts ~/.local/bin on PATH)
    curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
    export PATH="$HOME/.local/bin:$PATH"
fi
command -v uv >/dev/null 2>&1 || die "uv installation failed."
ok "$(uv --version)"

# ---- 4. Python + virtual environment ----------------------------------------
step "Creating virtual environment at $VENV_DIR (Python $PYTHON_VERSION, uv-managed)"
uv python install "$PYTHON_VERSION"
if [[ -x "$VENV_DIR/bin/python" ]]; then
    ok "Reusing existing venv: $("$VENV_DIR/bin/python" --version)"
else
    uv venv --python "$PYTHON_VERSION" --python-preference only-managed --seed "$VENV_DIR"
fi
VENV_PY="$VENV_DIR/bin/python"
export VIRTUAL_ENV="$VENV_DIR"   # every 'uv pip' call below targets this venv only

# ---- 5. LeRobot source ---------------------------------------------------------
step "Fetching LeRobot source ($LEROBOT_REF) into $LEROBOT_DIR"
if [[ -d "$LEROBOT_DIR/.git" ]]; then
    if [[ -n "$(git -C "$LEROBOT_DIR" status --porcelain)" ]]; then
        warn "Local changes in $LEROBOT_DIR - not updating the checkout."
    else
        git -C "$LEROBOT_DIR" fetch --tags origin
        git -C "$LEROBOT_DIR" checkout "$LEROBOT_REF"
        # fast-forward only when on a branch
        git -C "$LEROBOT_DIR" symbolic-ref -q HEAD >/dev/null && git -C "$LEROBOT_DIR" pull --ff-only
    fi
else
    git clone "$LEROBOT_REPO" "$LEROBOT_DIR"
    git -C "$LEROBOT_DIR" checkout "$LEROBOT_REF"
fi
ok "LeRobot at $(git -C "$LEROBOT_DIR" rev-parse --short HEAD)"

# ---- 6. Install LeRobot into the venv ---------------------------------------
step "Installing lerobot[$LEROBOT_EXTRAS] (editable) into the venv"
# LeRobot's pyproject pins torch/torchvision to the CUDA 12.8 index on Linux,
# which supports Blackwell GPUs (RTX 5090, sm_120).
uv pip install --python "$VENV_PY" -e "$LEROBOT_DIR[$LEROBOT_EXTRAS]"

if [[ -n "$TORCH_BACKEND" ]]; then
    step "Reinstalling torch/torchvision for $TORCH_BACKEND"
    tv="$("$VENV_PY" -c 'import torch;print(torch.__version__.split("+")[0])')"
    vv="$("$VENV_PY" -c 'import torchvision;print(torchvision.__version__.split("+")[0])')"
    uv pip install --python "$VENV_PY" --force-reinstall --no-deps \
        "torch==$tv" "torchvision==$vv" \
        --index-url "https://download.pytorch.org/whl/$TORCH_BACKEND"
fi

# ---- 7. Serial port permissions ----------------------------------------------
if [[ $SKIP_SERIAL -eq 0 ]]; then
    step "Configuring serial-port access for the SO-101 motor boards"
    ASSUME_YES=$ASSUME_YES bash "$REPO_DIR/scripts/setup_serial.sh"
fi

# ---- 8. Verify -----------------------------------------------------------------
if [[ $SKIP_VERIFY -eq 0 ]]; then
    step "Verifying the environment"
    "$VENV_PY" "$REPO_DIR/scripts/check_env.py" || warn "Some checks failed - see above."
fi

cat <<EOF

${c_grn}Installation finished.${c_off}

Activate the environment in every new terminal:

  source $REPO_DIR/activate.sh

Then use the LeRobot commands (see README.md), e.g.:
  lerobot-find-port
  lerobot-setup-motors --robot.type=so101_follower --robot.port=/dev/ttyACM0

If you were just added to the 'dialout' group, log out and back in once.
EOF
