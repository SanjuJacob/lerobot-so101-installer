# LeRobot SO-101 – one-command install for Ubuntu 24.04

Sets up [Hugging Face LeRobot](https://huggingface.co/docs/lerobot/main/en/installation) for the
[SO-101 arm](https://huggingface.co/docs/lerobot/en/so101) (leader + follower) on a fresh Ubuntu machine.

- **Isolated**: all Python packages go into `./.venv` (Python 3.12, managed by [uv](https://docs.astral.sh/uv/)). The system Python is never touched.
- **GPU ready**: PyTorch CUDA 12.8 wheels, which support Blackwell GPUs (RTX 5090, `sm_120`).
- **SO-101 ready**: Feetech motor SDK, recording, visualization, training (ACT, SmolVLA), serial-port permissions.
- **Easy commands**: a `so101` wrapper fills in ports, ids and cameras from one config file.

Target machine: Ubuntu 24.04.5 LTS, kernel 7.0, 96 GiB RAM, RTX 5090.

---

## 1. Prerequisite: NVIDIA driver

The RTX 5090 needs the **open** NVIDIA kernel module, version **≥ 570** (580+ recommended). Check with:

```bash
nvidia-smi
```

If that fails, install the driver first and reboot:

```bash
sudo ubuntu-drivers list            # shows the recommended *-open driver
sudo ubuntu-drivers install         # or: sudo apt install nvidia-driver-580-open
sudo reboot
```

> On a very new kernel (7.0), the driver module is built by DKMS. If `nvidia-smi` still fails after reboot,
> check `dkms status` and make sure the `linux-headers-$(uname -r)` package is installed.
> If Secure Boot is on, you will be asked to enroll a MOK key at the next boot.

The CUDA toolkit is **not** needed: PyTorch ships its own CUDA runtime.
The "CUDA Version" shown by `nvidia-smi` (e.g. 13.2 with driver 595) is only the *highest* CUDA version
the driver supports, not something installed. Such a driver runs the default CUDA 12.8 PyTorch wheels
as well as `--torch cu130`.

## 2. Install

```bash
git clone https://github.com/<your-user>/<this-repo>.git lerobot-so101
cd lerobot-so101
./install.sh
```

What `install.sh` does:

| Step | What | Where |
|------|------|-------|
| 1 | `apt install` git, ffmpeg, build tools, libav dev headers, v4l-utils | system (no Python packages) |
| 2 | Checks the NVIDIA driver version | – |
| 3 | Installs `uv` if missing | `~/.local/bin` |
| 4 | Installs Python 3.12 (uv-managed) and creates the venv | `./.venv` |
| 5 | Clones LeRobot | `./lerobot` |
| 6 | `uv pip install -e "lerobot[feetech,core_scripts,training,smolvla]"` | `./.venv` only |
| 7 | Adds you to `dialout`, adds a udev rule for the motor boards, offers to remove `brltty` | `/etc/udev/rules.d` |
| 8 | Creates `config/so101.env` and links the `so101` command | `~/.local/bin/so101` |
| 9 | Runs `scripts/check_env.py` (GPU, torch, Feetech SDK, ffmpeg, CLI tools) | – |

**Log out and back in once** afterwards so the `dialout` group membership applies.

### Options

```bash
./install.sh --help
./install.sh --extras "feetech,core_scripts,training,smolvla,pi"   # add Pi0/Pi0.5 policy deps
./install.sh --ref <tag-or-commit>  # pin a LeRobot release/commit instead of main (reproducible lab setups)
./install.sh --torch cu130         # use CUDA 13.0 torch wheels (driver >= 580)
./install.sh --no-apt --no-serial  # only (re)build the Python env
```

The same values can be set with env vars: `LEROBOT_EXTRAS`, `LEROBOT_REF`, `TORCH_BACKEND`, `VENV_DIR`.
Re-running `./install.sh` is safe: it reuses the venv and updates the LeRobot checkout.

## 3. Using the environment

Two equivalent ways:

```bash
# a) wrapper - no activation needed, values come from config/so101.env
so101 help

# b) plain LeRobot commands, exactly as in the official docs
source activate.sh
lerobot-find-port
```

Check everything at any time:

```bash
so101 check
```

## 4. SO-101 workflow

Edit `config/so101.env` (ports, arm ids, cameras, Hugging Face user, dataset name, task).
Any value can also be overridden for a single run, e.g. `FOLLOWER_PORT=/dev/ttyACM1 so101 teleop`,
and any extra flag is passed through to the LeRobot command, e.g. `so101 record --dataset.num_episodes=20`.

| Step | Wrapper | Equivalent LeRobot command |
|------|---------|----------------------------|
| Find the port of each arm | `so101 find-port` | `lerobot-find-port` |
| Stable port names (optional, recommended) | `so101 bind-ports` | – (creates `/dev/so101_follower`, `/dev/so101_leader`) |
| Set motor ids/baudrate – follower (once) | `so101 setup-follower` | `lerobot-setup-motors --robot.type=so101_follower --robot.port=...` |
| Set motor ids/baudrate – leader (once) | `so101 setup-leader` | `lerobot-setup-motors --teleop.type=so101_leader --teleop.port=...` |
| Calibrate follower | `so101 calibrate-follower` | `lerobot-calibrate --robot.type=so101_follower --robot.port=... --robot.id=...` |
| Calibrate leader | `so101 calibrate-leader` | `lerobot-calibrate --teleop.type=so101_leader --teleop.port=... --teleop.id=...` |
| Find cameras | `so101 find-cameras` | `lerobot-find-cameras opencv` |
| Teleoperate | `so101 teleop` | `lerobot-teleoperate --robot.* --teleop.* [--robot.cameras=... --display_data=true]` |
| Log in to the Hub | `so101 hf-login` | `hf auth login --add-to-git-credential` |
| Record a dataset | `so101 record` | `lerobot-record ... --dataset.repo_id=$HF_USER/$DATASET_NAME ...` |
| Replay episode 0 | `so101 replay 0` | `lerobot-replay ... --dataset.episode=0` |
| Train a policy on the GPU | `so101 train` | `lerobot-train --policy.type=act --policy.device=cuda ...` |
| Run a trained policy | `so101 rollout $HF_USER/act_so101_test` | `lerobot-rollout --strategy.type=base --policy.path=...` |
| Anything else | `so101 run lerobot-eval --help` | – |

Every wrapper command prints the exact LeRobot command it runs (line starting with `+`).

### Typical first session

```bash
so101 find-port            # follow prompts for each arm, write ports into config/so101.env
so101 bind-ports           # optional: then set FOLLOWER_PORT=/dev/so101_follower, LEADER_PORT=/dev/so101_leader
so101 setup-follower       # connect one motor at a time as instructed
so101 setup-leader
so101 calibrate-follower   # middle position, Enter, then move every joint through its full range
so101 calibrate-leader
so101 teleop
```

Recording and training:

```bash
so101 hf-login                                  # token with write access from huggingface.co/settings/tokens
so101 find-cameras                              # then set CAMERAS in config/so101.env
so101 record                                    # → / n: next episode, ← / r: re-record, Esc / q: stop
so101 train                                     # checkpoints in ./outputs/train/act_so101_test
so101 run lerobot-train --config_path=outputs/train/act_so101_test/checkpoints/last/pretrained_model/train_config.json --resume=true   # resume
so101 rollout outputs/train/act_so101_test/checkpoints/last/pretrained_model
```

Calibration files are stored in `~/.cache/huggingface/lerobot/calibration/` under the arm `id`, and
datasets in `~/.cache/huggingface/lerobot/<repo_id>`. Use the same ids for teleop, record and rollout.

## 5. Repository layout

```
install.sh               one-shot installer
so101                    wrapper CLI (linked to ~/.local/bin/so101)
activate.sh              `source` it to activate the venv in your shell
uninstall.sh             removes .venv, lerobot/ and the so101 link
config/so101.env.example template for your ports/ids/cameras (copied to config/so101.env)
scripts/check_env.py     environment / GPU self-test
scripts/setup_serial.sh  dialout group, udev rule, brltty fix
scripts/bind_ports.sh    persistent /dev/so101_follower and /dev/so101_leader names
```

`.venv/`, `lerobot/`, `outputs/` and `config/so101.env` are git-ignored, so the repo stays small and
each machine keeps its own settings.

## 6. Troubleshooting

| Problem | Fix |
|---------|-----|
| `Permission denied: '/dev/ttyACM0'` | Log out/in after install (dialout group), or replug the arm. Quick fix: `sudo chmod 666 /dev/ttyACM0` |
| Port disappears right after plugging in | `brltty` grabbed it: `sudo apt remove brltty` (or re-run `scripts/setup_serial.sh`) |
| Ports swap between ttyACM0/ttyACM1 | `so101 bind-ports` and use `/dev/so101_follower` / `/dev/so101_leader` |
| Motor setup error | Check power supply, USB and the 3-pin cable; on Waveshare boards set both jumpers to **B** (USB) |
| `CUDA not available` in `so101 check` | NVIDIA driver not loaded – see section 1, then `./install.sh --no-apt --no-serial` |
| `no kernel image is available for execution on the device` | torch build lacks `sm_120`: `./install.sh --no-apt --no-serial --torch cu128` (or `cu130`) |
| Recording keys do nothing (Wayland, Ubuntu default) | Keep the terminal running `so101 record` focused; letters `n` / `r` / `q` also work |
| Video encoding errors | `ffmpeg -encoders | grep svtav1`; Ubuntu's ffmpeg works with TorchCodec ≥ 0.10 (torch ≥ 2.10) |
| Build errors while installing | `./install.sh` again (apt step installs cmake, build-essential, libav*-dev) |

## Uninstall

```bash
./uninstall.sh           # removes .venv, lerobot/, ~/.local/bin/so101
./uninstall.sh --udev    # also removes the udev rules
```

## References

- LeRobot installation: <https://huggingface.co/docs/lerobot/main/en/installation>
- SO-101 guide: <https://huggingface.co/docs/lerobot/en/so101>
- Imitation learning on real robots (teleop, record, train): <https://huggingface.co/docs/lerobot/en/il_robots>
- Hardware / BOM: <https://github.com/TheRobotStudio/SO-ARM100>
