# LeRobot SO-101 Installer for Ubuntu

**One command to set up [Hugging Face LeRobot](https://github.com/huggingface/lerobot) for the SO-101 robot arm on a fresh Ubuntu machine, in an isolated Python environment.**

![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?logo=ubuntu&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)
![CUDA](https://img.shields.io/badge/CUDA-12.8%20%7C%2013.0-76B900?logo=nvidia&logoColor=white)
![GPU](https://img.shields.io/badge/RTX%2050xx-supported-76B900?logo=nvidia&logoColor=white)

```bash
git clone https://github.com/YOUR-USERNAME/lerobot-so101-installer.git
cd lerobot-so101-installer
./install.sh
```

After that, every SO-101 step from the [official guide](https://huggingface.co/docs/lerobot/en/so101) is one short command:

```bash
so101 find-port
so101 calibrate-follower
so101 teleop
so101 record
so101 train
```

---

## Contents

- [Why this exists](#why-this-exists)
- [Requirements](#requirements)
- [Installation](#installation)
- [Is it safe for my system?](#is-it-safe-for-my-system)
- [Using it](#using-it)
- [Command reference](#command-reference)
- [Configuration](#configuration)
- [Install options](#install-options)
- [Compatibility](#compatibility)
- [Troubleshooting](#troubleshooting)
- [Updating and uninstalling](#updating-and-uninstalling)
- [Repository layout](#repository-layout)
- [Credits and license](#credits-and-license)

---

## Why this exists

The official LeRobot setup involves several steps: a Python 3.12 environment, PyTorch with the right CUDA build, ffmpeg, the Feetech motor SDK, USB serial permissions, and long command lines with ports and ids for every step. This repo does all of it reproducibly:

- **Isolated.** Every Python package goes into `./.venv` inside this folder. The system Python is never used or changed.
- **GPU ready.** Installs PyTorch with CUDA 12.8 (or 13.0 if you choose), which supports the newest NVIDIA GPUs, including the RTX 5090.
- **SO-101 ready.** Feetech motor SDK, recording, Rerun visualization, training (ACT, SmolVLA), Hugging Face Hub CLI.
- **USB just works.** Fixes serial-port permissions, the `brltty` problem on Ubuntu, and optionally gives your arms stable names (`/dev/so101_follower`, `/dev/so101_leader`).
- **Short commands.** The `so101` wrapper fills in ports, arm ids and cameras from one config file, and prints the full LeRobot command it runs so you can learn from it.
- **Self-test.** `so101 check` verifies the GPU, PyTorch, the motor SDK, and a real video encode/decode.

## Requirements

| | |
|---|---|
| **OS** | Ubuntu 24.04 LTS (recommended) or 22.04 LTS, x86_64. See [Compatibility](#compatibility) |
| **GPU** (optional) | NVIDIA GPU with driver **≥ 570**. Without a GPU, everything works except fast training |
| **Disk** | ~15 GB free (PyTorch + CUDA libraries + LeRobot) |
| **Access** | A user account with `sudo` (asked only for system packages and USB rules) |
| **Robot** | SO-101 leader + follower arms with their USB motor boards ([build guide](https://github.com/TheRobotStudio/SO-ARM100)) |

### NVIDIA driver

Check whether a driver is loaded:

```bash
nvidia-smi
```

If it shows a driver version of 570 or higher, you're done. The "CUDA Version" in the top right is just the *highest* CUDA version that driver supports; you do **not** need to install the CUDA toolkit, because PyTorch brings its own.

If `nvidia-smi` fails, install the recommended driver and reboot (RTX 50-series cards need the `-open` variant):

```bash
sudo ubuntu-drivers install
sudo reboot
```

> The installer only *checks* the driver. It never installs, removes or changes it.

## Installation

```bash
git clone https://github.com/YOUR-USERNAME/lerobot-so101-installer.git
cd lerobot-so101-installer
./install.sh
```

Run it as your normal user, **not** with `sudo`. It asks for your password when it needs it. It takes about 5–15 minutes depending on your internet speed.

When it finishes, **log out and log back in once** so USB-port access applies. Then:

```bash
so101 check
```

<details>
<summary><b>What install.sh does, step by step</b></summary>

| # | Step | Where it goes |
|---|------|---------------|
| 1 | `apt install` git, curl, ffmpeg, build tools, libav/libevdev headers, v4l-utils | system packages |
| 2 | Checks the NVIDIA driver version (read-only) | – |
| 3 | Installs [uv](https://docs.astral.sh/uv/) if missing | `~/.local/bin` |
| 4 | Installs Python 3.12 (uv-managed) and creates the virtual environment | `./.venv` |
| 5 | Clones LeRobot from GitHub | `./lerobot` |
| 6 | Installs `lerobot[feetech,core_scripts,training,smolvla]` + PyTorch (CUDA 12.8) | `./.venv` only |
| 7 | Adds you to the `dialout` group, adds a udev rule for the motor boards, offers to remove `brltty` | `/etc/udev/rules.d` |
| 8 | Creates your config and the `so101` command | `config/so101.env`, `~/.local/bin/so101` |
| 9 | Runs the self-test | – |

Re-running `./install.sh` is safe: it reuses the environment and updates LeRobot.
</details>

## Is it safe for my system?

Yes. **Never touched:** GPU drivers, the kernel, the system Python and its packages, boot/display settings. It never runs `apt upgrade`. All Python packages, including PyTorch's CUDA libraries, live inside `./.venv`, and deleting that folder removes them completely.

The only changes outside this folder, each one reversible:

| Change | Why | How to undo |
|--------|-----|-------------|
| apt packages: git, curl, ffmpeg, build-essential, cmake, pkg-config, libav\*-dev, libevdev-dev, v4l-utils | video, building packages, cameras | `sudo apt remove <package>` |
| `uv` in `~/.local/bin`, its Python in `~/.local/share/uv` (your `.bashrc` is not edited) | creates the isolated environment | `rm ~/.local/bin/uv ~/.local/bin/uvx && rm -rf ~/.local/share/uv` |
| `~/.local/bin/so101` link | the wrapper command | `./uninstall.sh` |
| your user added to `dialout` | permission to use USB serial ports | `sudo gpasswd -d $USER dialout` |
| `/etc/udev/rules.d/99-so101-serial.rules` | access to the motor boards (USB vendor `1a86` only) | `./uninstall.sh --udev` |
| `brltty` removed, **only if you answer yes** | this braille service hijacks the arm's USB adapter | `sudo apt install brltty` |

Want even less? `./install.sh --no-apt --no-serial` touches only this folder and `~/.local`.

To double-check that apt won't touch any NVIDIA package, do a dry run first:

```bash
sudo apt-get install -s ffmpeg build-essential cmake pkg-config libavformat-dev libavcodec-dev \
  libavdevice-dev libavutil-dev libswscale-dev libswresample-dev libavfilter-dev \
  libevdev-dev v4l-utils | grep -i nvidia     # no output = nothing NVIDIA-related changes
```

## Using it

There are two equivalent ways to run LeRobot.

**A. The `so101` wrapper** (recommended). No activation needed. Ports, ids and cameras come from `config/so101.env`:

```bash
so101 teleop
```

**B. Plain LeRobot commands**, exactly as in the official docs:

```bash
source activate.sh        # activates ./.venv in this terminal
lerobot-teleoperate --robot.type=so101_follower --robot.port=/dev/ttyACM0 ...
deactivate                # leave the environment
```

### First-time robot setup

Follow the [official SO-101 guide](https://huggingface.co/docs/lerobot/en/so101) for assembly; these are the matching commands:

```bash
# 1. Which USB port is which arm? Follow the prompts, then put the ports into config/so101.env
so101 find-port

# 2. (Recommended) give the arms fixed names so ttyACM0/ttyACM1 never swap
so101 bind-ports           # then set FOLLOWER_PORT=/dev/so101_follower and LEADER_PORT=/dev/so101_leader

# 3. Set motor ids and baudrate, one motor at a time (only once per arm)
so101 setup-follower
so101 setup-leader

# 4. Calibrate: put the arm in the middle of its range, press Enter, move every joint through its full range
so101 calibrate-follower
so101 calibrate-leader

# 5. Move the leader, the follower follows
so101 teleop
```

### Recording, training, deploying

Follow the [imitation learning tutorial](https://huggingface.co/docs/lerobot/en/il_robots):

```bash
so101 hf-login             # paste a token with WRITE access from https://huggingface.co/settings/tokens
so101 find-cameras         # then set CAMERAS in config/so101.env
so101 teleop               # with cameras set, opens a live Rerun view

so101 record               # keys: → or n = next episode, ← or r = re-record, Esc or q = stop
so101 replay 0             # replay episode 0 on the follower

so101 train                # trains ACT on the GPU, checkpoints in ./outputs/train/
so101 rollout outputs/train/act_so101_test/checkpoints/last/pretrained_model
```

Resume an interrupted training:

```bash
so101 run lerobot-train --resume=true \
  --config_path=outputs/train/act_so101_test/checkpoints/last/pretrained_model/train_config.json
```

**Tips**

- Any extra flag is passed to LeRobot: `so101 record --dataset.num_episodes=50 --dataset.push_to_hub=false`
- Override a config value for one run: `FOLLOWER_PORT=/dev/ttyACM1 so101 teleop`
- Every command prints the exact LeRobot command it runs (the line starting with `+`).
- Calibration files live in `~/.cache/huggingface/lerobot/calibration/`, named after the arm id. Keep the same ids for teleop, record and rollout.
- Datasets are stored in `~/.cache/huggingface/lerobot/<user>/<dataset>`.

## Command reference

| Command | What it does | Runs |
|---------|--------------|------|
| `so101 check` | Self-test: venv, GPU, PyTorch, motor SDK, video encode/decode | `scripts/check_env.py` |
| `so101 info` | Version info for bug reports | `lerobot-info` |
| `so101 ports` | List serial devices | – |
| `so101 find-port` | Identify which port belongs to which arm | `lerobot-find-port` |
| `so101 bind-ports` | Create `/dev/so101_follower` and `/dev/so101_leader` | `scripts/bind_ports.sh` |
| `so101 find-cameras` | List cameras and save test images | `lerobot-find-cameras opencv` |
| `so101 setup-follower` | Set follower motor ids/baudrate | `lerobot-setup-motors --robot.type=so101_follower` |
| `so101 setup-leader` | Set leader motor ids/baudrate | `lerobot-setup-motors --teleop.type=so101_leader` |
| `so101 calibrate-follower` | Calibrate the follower | `lerobot-calibrate --robot.type=so101_follower` |
| `so101 calibrate-leader` | Calibrate the leader | `lerobot-calibrate --teleop.type=so101_leader` |
| `so101 teleop` | Teleoperate (adds cameras + Rerun view if configured) | `lerobot-teleoperate` |
| `so101 hf-login` | Log in to the Hugging Face Hub | `hf auth login` |
| `so101 record` | Record a dataset | `lerobot-record` |
| `so101 replay [N]` | Replay episode N (default 0) | `lerobot-replay` |
| `so101 train` | Train a policy | `lerobot-train` |
| `so101 rollout PATH` | Run a trained policy on the robot | `lerobot-rollout` |
| `so101 run CMD ...` | Run any command inside the environment | – |
| `so101 shell` | Open a new shell with the environment active | – |
| `so101 help` | Show help and the current config | – |

## Configuration

`install.sh` creates `config/so101.env` from [`config/so101.env.example`](config/so101.env.example). It is git-ignored, so each machine keeps its own settings.

```bash
FOLLOWER_PORT=/dev/ttyACM0             # or /dev/so101_follower after `so101 bind-ports`
LEADER_PORT=/dev/ttyACM1
FOLLOWER_ID=my_awesome_follower_arm    # names the calibration file
LEADER_ID=my_awesome_leader_arm

CAMERAS="{ front: {type: opencv, index_or_path: /dev/video0, width: 640, height: 480, fps: 30}}"

HF_USER=""                             # empty = detect from `hf auth whoami`
DATASET_NAME=so101_test
TASK="Grab the black cube"
NUM_EPISODES=5
EPISODE_TIME_S=60
RESET_TIME_S=10
PUSH_TO_HUB=true

POLICY_TYPE=act                        # e.g. act, smolvla, diffusion
POLICY_DEVICE=cuda
WANDB_ENABLE=false
```

## Install options

```bash
./install.sh --help
```

| Option | Env variable | Default | Purpose |
|--------|--------------|---------|---------|
| `--extras LIST` | `LEROBOT_EXTRAS` | `feetech,core_scripts,training,smolvla` | LeRobot extras, e.g. add `pi`, `diffusion`, `intelrealsense` |
| `--ref REF` | `LEROBOT_REF` | `main` | LeRobot branch, tag or commit; pin one for reproducible lab setups |
| `--torch BACKEND` | `TORCH_BACKEND` | (LeRobot default, `cu128`) | PyTorch CUDA build, e.g. `cu130` for drivers ≥ 580 |
| `--venv DIR` | `VENV_DIR` | `./.venv` | Location of the virtual environment |
| `--no-apt` | | | Skip system packages |
| `--no-serial` | | | Skip USB permission setup |
| `--no-verify` | | | Skip the self-test |
| `-y`, `--yes` | | | Answer yes to all prompts |

Examples:

```bash
./install.sh --extras "feetech,core_scripts,training,smolvla,pi"   # add Pi0 / Pi0.5 support
./install.sh --torch cu130                                         # CUDA 13.0 PyTorch
./install.sh --no-apt --no-serial                                  # rebuild only the Python environment
```

## Compatibility

The installer brings its own Python 3.12, so Ubuntu's Python version doesn't matter. What varies between releases is glibc (PyTorch needs ≥ 2.28) and the system ffmpeg used to *decode* dataset videos.

| Ubuntu | Status |
|--------|--------|
| 24.04 LTS | ✅ primary target |
| 22.04 LTS | ✅ expected to work |
| 24.10 / 25.x / 26.04 | ✅ expected to work |
| 20.04 LTS | ⚠️ probably works, out of standard support |
| 18.04 and older | ❌ glibc too old for current PyTorch |

- **CPU:** x86_64 only. ARM boards and Jetson need a different PyTorch build.
- **Ubuntu-based distros** (Linux Mint, Pop!_OS, Kubuntu, …) behave like their Ubuntu base; the installer just prints a warning.
- `so101 check` encodes and decodes a test video, so you know right away whether a machine works. If only the **decode** test fails, use the PyAV decoder: `so101 train --dataset.video_backend=pyav`.

Developed for: Ubuntu 24.04.5 LTS, kernel 7.0, NVIDIA RTX 5090 (driver 595), 96 GB RAM.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `so101: command not found` | Log out and back in (Ubuntu adds `~/.local/bin` to PATH at login), or run `./so101` from this folder |
| `Permission denied: '/dev/ttyACM0'` | Log out/in after install, or unplug and replug the arm. Quick fix: `sudo chmod 666 /dev/ttyACM0` |
| Arm's port disappears right after plugging in | `brltty` grabbed it: `sudo apt remove brltty` |
| Ports swap between ttyACM0 and ttyACM1 | `so101 bind-ports`, then use `/dev/so101_follower` / `/dev/so101_leader` |
| Error during `setup-follower` / `setup-leader` | Check power supply, USB and the 3-pin cable; only one motor connected at a time; on Waveshare boards set both jumpers to **B** (USB) |
| `CUDA not available` in `so101 check` | Driver not loaded: see [NVIDIA driver](#nvidia-driver), then `./install.sh --no-apt --no-serial` |
| `no kernel image is available for execution on the device` | PyTorch build doesn't support your GPU: `./install.sh --no-apt --no-serial --torch cu128` (or `cu130`) |
| Recording keys do nothing | Keep the terminal running `so101 record` focused; `n` / `r` / `q` also work (needed on Wayland) |
| Video decode test fails | System ffmpeg doesn't match TorchCodec: add `--dataset.video_backend=pyav` |
| Build errors during install | Re-run `./install.sh` (the apt step installs the compilers and headers) |
| Anything else | Run `so101 info` and include its output when asking on the [LeRobot Discord](https://discord.com/invite/s3KuuzsPFb) or opening an issue here |

## Updating and uninstalling

```bash
git pull && ./install.sh --no-apt --no-serial     # update this repo and LeRobot

./uninstall.sh                                    # remove .venv, lerobot/ and the so101 command
./uninstall.sh --udev                             # also remove the USB udev rules
```

Uninstall keeps your `config/so101.env`, `outputs/`, and recorded datasets / calibrations in `~/.cache/huggingface`.

## Repository layout

```
├── install.sh                 one-shot installer
├── so101                      wrapper command (linked to ~/.local/bin/so101)
├── activate.sh                `source activate.sh` to use plain lerobot-* commands
├── uninstall.sh               removes everything install.sh created in this folder
├── config/
│   └── so101.env.example      template for ports, ids, cameras, dataset, training
└── scripts/
    ├── check_env.py           self-test (GPU, PyTorch, motor SDK, video)
    ├── setup_serial.sh        dialout group, udev rule, brltty fix
    └── bind_ports.sh          stable /dev/so101_follower and /dev/so101_leader names
```

Created at install time and git-ignored: `.venv/`, `lerobot/`, `outputs/`, `config/so101.env`.

## Credits and license

This is a community installer and is **not affiliated with Hugging Face or The Robot Studio**. All the robotics work is done by:

- [LeRobot](https://github.com/huggingface/lerobot) by Hugging Face, Apache-2.0
- [SO-ARM100 / SO-101](https://github.com/TheRobotStudio/SO-ARM100) hardware by The Robot Studio
- [uv](https://github.com/astral-sh/uv) by Astral

Official documentation:
[installation](https://huggingface.co/docs/lerobot/main/en/installation) ·
[SO-101](https://huggingface.co/docs/lerobot/en/so101) ·
[imitation learning on real robots](https://huggingface.co/docs/lerobot/en/il_robots)

Issues and pull requests are welcome, especially test reports from other Ubuntu versions and GPUs.
