# LeRobot SO-101 Installer for Ubuntu

**One script to install [Hugging Face LeRobot](https://github.com/huggingface/lerobot) for the SO-101 robot arm on Ubuntu, inside an isolated Python virtual environment.**

![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?logo=ubuntu&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)
![CUDA](https://img.shields.io/badge/CUDA-12.8%20%7C%2013.0-76B900?logo=nvidia&logoColor=white)

```bash
git clone https://github.com/SanjuJacob/lerobot-so101-installer.git
cd lerobot-so101-installer
./install.sh
source activate.sh
```

> This is an unofficial community installer. It automates the steps described in the official
> [LeRobot installation guide](https://huggingface.co/docs/lerobot/main/en/installation) and
> [SO-101 guide](https://huggingface.co/docs/lerobot/en/so101). See [References and attribution](#references-and-attribution).

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Install options](#install-options)
- [Compatibility](#compatibility)
- [Troubleshooting](#troubleshooting)
- [Updating and uninstalling](#updating-and-uninstalling)
- [Repository layout](#repository-layout)
- [References and attribution](#references-and-attribution)

---

## Features

- **Isolated.** All Python packages are installed into `./.venv` inside this folder. The system Python is not used or changed.
- **GPU ready.** Installs PyTorch with CUDA 12.8 (or 13.0 on request), which supports current NVIDIA GPUs including the RTX 50-series.
- **SO-101 ready.** Installs LeRobot with the Feetech motor SDK, recording, visualization and training extras.
- **USB serial access.** Sets up permissions for the SO-101 motor boards so you don't need `sudo chmod` after every replug.
- **Self-test.** Checks the GPU, PyTorch, the motor SDK and video encoding/decoding at the end of the install.

## Requirements

| | |
|---|---|
| **OS** | Ubuntu 24.04 LTS (recommended) or 22.04 LTS, x86_64 |
| **GPU** (optional) | NVIDIA GPU with driver **≥ 570**. Without a GPU, everything works except fast training |
| **Disk** | ~15 GB free |
| **Access** | A user account with `sudo` |

### NVIDIA driver

Check that a driver is loaded:

```bash
nvidia-smi
```

A driver version of 570 or higher is enough. The "CUDA Version" shown there is the *highest* CUDA version the driver supports; you do **not** need to install the CUDA toolkit, because PyTorch brings its own CUDA libraries.

If `nvidia-smi` fails, install the recommended driver and reboot (RTX 50-series cards need the `-open` variant):

```bash
sudo ubuntu-drivers install
sudo reboot
```

The installer only checks the driver version; it does not install or modify drivers.

## Installation

```bash
git clone https://github.com/SanjuJacob/lerobot-so101-installer.git
cd lerobot-so101-installer
./install.sh
```

Run it as your normal user, **not** with `sudo`; it asks for your password when needed. When it finishes, **log out and log back in once** so the USB serial permissions take effect.

What `install.sh` does:

| # | Step |
|---|------|
| 1 | Installs system packages with apt: git, curl, ffmpeg, build tools, libav/libevdev headers, v4l-utils |
| 2 | Checks the NVIDIA driver version |
| 3 | Installs [uv](https://docs.astral.sh/uv/) to `~/.local/bin` if it is missing |
| 4 | Installs Python 3.12 (uv-managed) and creates the virtual environment `./.venv` |
| 5 | Clones LeRobot from GitHub into `./lerobot` |
| 6 | Installs `lerobot[feetech,core_scripts,training,smolvla]` and PyTorch into `./.venv` |
| 7 | Adds your user to the `dialout` group, adds a udev rule for the motor boards, and offers to remove `brltty` (it blocks the boards' USB adapter) |
| 8 | Runs the self-test `scripts/check_env.py` |

Running `./install.sh` again is safe: it reuses the environment and updates LeRobot.

## Usage

Activate the environment in every new terminal:

```bash
source activate.sh      # in this folder
deactivate              # to leave it again
```

All `lerobot-*` commands are then available. The steps below follow the official
[SO-101 guide](https://huggingface.co/docs/lerobot/en/so101) and
[imitation learning tutorial](https://huggingface.co/docs/lerobot/en/il_robots); see those pages for full explanations.
Replace the ports and ids with your own.

**Check the installation**

```bash
python scripts/check_env.py
```

**1. Find the USB port of each arm**

```bash
lerobot-find-port
```

**2. Set up the motors** (once per arm, one motor connected at a time)

```bash
lerobot-setup-motors --robot.type=so101_follower --robot.port=/dev/ttyACM0
lerobot-setup-motors --teleop.type=so101_leader  --teleop.port=/dev/ttyACM1
```

**3. Calibrate**

```bash
lerobot-calibrate --robot.type=so101_follower --robot.port=/dev/ttyACM0 --robot.id=my_follower_arm
lerobot-calibrate --teleop.type=so101_leader  --teleop.port=/dev/ttyACM1 --teleop.id=my_leader_arm
```

**4. Teleoperate**

```bash
lerobot-teleoperate \
    --robot.type=so101_follower --robot.port=/dev/ttyACM0 --robot.id=my_follower_arm \
    --teleop.type=so101_leader  --teleop.port=/dev/ttyACM1 --teleop.id=my_leader_arm
```

**5. Cameras**

```bash
lerobot-find-cameras opencv
```

Add them with, for example,
`--robot.cameras="{ front: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 30}}" --display_data=true`.

**6. Record a dataset**

```bash
hf auth login --add-to-git-credential          # token with write access
HF_USER=$(NO_COLOR=1 hf auth whoami | awk -F': *' 'NR==1 {print $2}')

lerobot-record \
    --robot.type=so101_follower --robot.port=/dev/ttyACM0 --robot.id=my_follower_arm \
    --robot.cameras="{ front: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 30}}" \
    --teleop.type=so101_leader  --teleop.port=/dev/ttyACM1 --teleop.id=my_leader_arm \
    --display_data=true \
    --dataset.repo_id=${HF_USER}/so101_test \
    --dataset.num_episodes=5 \
    --dataset.single_task="Grab the black cube"
```

Keys while recording: `→` / `n` next episode, `←` / `r` re-record, `Esc` / `q` stop.

**7. Replay an episode**

```bash
lerobot-replay \
    --robot.type=so101_follower --robot.port=/dev/ttyACM0 --robot.id=my_follower_arm \
    --dataset.repo_id=${HF_USER}/so101_test --dataset.episode=0
```

**8. Train a policy**

```bash
lerobot-train \
    --dataset.repo_id=${HF_USER}/so101_test \
    --policy.type=act \
    --output_dir=outputs/train/act_so101_test \
    --job_name=act_so101_test \
    --policy.device=cuda \
    --policy.repo_id=${HF_USER}/act_so101_test
```

**9. Run the trained policy**

```bash
lerobot-rollout \
    --strategy.type=base \
    --policy.path=outputs/train/act_so101_test/checkpoints/last/pretrained_model \
    --robot.type=so101_follower --robot.port=/dev/ttyACM0 --robot.id=my_follower_arm \
    --robot.cameras="{ front: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 30}}" \
    --task="Grab the black cube" --duration=60
```

Calibration files are saved in `~/.cache/huggingface/lerobot/calibration/` under the arm id, so use the same ids every time. Datasets are stored in `~/.cache/huggingface/lerobot/`.

## Install options

```bash
./install.sh --help
```

| Option | Env variable | Default | Purpose |
|--------|--------------|---------|---------|
| `--extras LIST` | `LEROBOT_EXTRAS` | `feetech,core_scripts,training,smolvla` | LeRobot extras, e.g. add `pi`, `diffusion`, `intelrealsense` |
| `--ref REF` | `LEROBOT_REF` | `main` | LeRobot branch, tag or commit to install |
| `--torch BACKEND` | `TORCH_BACKEND` | LeRobot default (`cu128`) | PyTorch CUDA build, e.g. `cu130` for drivers ≥ 580 |
| `--venv DIR` | `VENV_DIR` | `./.venv` | Location of the virtual environment |
| `--no-apt` | | | Skip system packages |
| `--no-serial` | | | Skip USB serial permission setup |
| `--no-verify` | | | Skip the self-test |
| `-y`, `--yes` | | | Answer yes to all prompts |

## Compatibility

The installer brings its own Python 3.12, so Ubuntu's Python version does not matter. What differs between releases is glibc (PyTorch needs ≥ 2.28) and the system ffmpeg used to decode dataset videos.

| Ubuntu | Status |
|--------|--------|
| 24.04 LTS | ✅ primary target |
| 22.04 LTS | ✅ expected to work |
| 24.10 / 25.x / 26.04 | ✅ expected to work |
| 20.04 LTS | ⚠️ probably works, out of standard support |
| 18.04 and older | ❌ glibc too old for current PyTorch |

- **CPU:** x86_64 only. ARM boards and Jetson need a different PyTorch build.
- **Ubuntu-based distributions** (Linux Mint, Pop!_OS, …) behave like their Ubuntu base.
- If only the video **decode** self-test fails, use the PyAV decoder: add `--dataset.video_backend=pyav` to `lerobot-train`.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Permission denied: '/dev/ttyACM0'` | Log out and back in after installing, or unplug and replug the arm. Quick fix: `sudo chmod 666 /dev/ttyACM0` |
| The arm's port disappears right after plugging in | `brltty` took it: `sudo apt remove brltty` |
| Ports swap between ttyACM0 and ttyACM1 | Run `lerobot-find-port` again, or always use the same USB sockets |
| Error during `lerobot-setup-motors` | Check power, USB and the 3-pin cable; connect only one motor at a time; on Waveshare boards set both jumpers to **B** (USB) |
| `CUDA not available` in the self-test | Driver not loaded: see [NVIDIA driver](#nvidia-driver), then `./install.sh --no-apt --no-serial` |
| `no kernel image is available for execution on the device` | PyTorch build doesn't match the GPU: `./install.sh --no-apt --no-serial --torch cu128` (or `cu130`) |
| Recording keys do nothing | Keep the terminal running `lerobot-record` focused; `n` / `r` / `q` also work |
| Build errors during install | Re-run `./install.sh` (the apt step installs the compilers and headers) |

For LeRobot questions, see the [LeRobot documentation](https://huggingface.co/docs/lerobot) and [Discord](https://discord.com/invite/s3KuuzsPFb). For problems with this installer, open an issue in this repository and include the output of `lerobot-info`.

## Updating and uninstalling

```bash
git pull && ./install.sh --no-apt --no-serial     # update this installer and LeRobot

./uninstall.sh                                    # remove .venv and lerobot/
./uninstall.sh --udev                             # also remove the USB udev rule
```

Recorded datasets and calibration files in `~/.cache/huggingface` are kept.

## Repository layout

```
├── install.sh              installer
├── activate.sh             `source activate.sh` to activate the environment
├── uninstall.sh            removes what install.sh created in this folder
├── NOTICE                  attribution and third-party notices
└── scripts/
    ├── check_env.py        self-test (GPU, PyTorch, motor SDK, video)
    └── setup_serial.sh     dialout group, udev rule, brltty fix
```

Created at install time and git-ignored: `.venv/` and `lerobot/`.

## References and attribution

This repository contains only installation scripts. It does **not** include or redistribute LeRobot's source code: LeRobot is downloaded from its official GitHub repository during installation and keeps its own license.

The installation steps and the example commands in this README are based on, and adapted from, the official LeRobot documentation by Hugging Face:

- LeRobot installation guide: <https://huggingface.co/docs/lerobot/main/en/installation>
- SO-101 guide: <https://huggingface.co/docs/lerobot/en/so101>
- Imitation learning on real-world robots: <https://huggingface.co/docs/lerobot/en/il_robots>
- LeRobot source code (Apache License 2.0): <https://github.com/huggingface/lerobot>

Other projects used:

- SO-ARM100 / SO-101 hardware by The Robot Studio: <https://github.com/TheRobotStudio/SO-ARM100>
- uv by Astral: <https://github.com/astral-sh/uv>
- PyTorch: <https://pytorch.org>

LeRobot, Hugging Face, SO-101 and other names are the property of their respective owners. This project is not affiliated with or endorsed by Hugging Face or The Robot Studio. See [NOTICE](NOTICE) for details.
