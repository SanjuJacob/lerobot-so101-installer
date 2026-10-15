"""Sanity-check the LeRobot / SO-101 environment.

Run with the venv's interpreter:  .venv/bin/python scripts/check_env.py
(or simply:  so101 check)
"""

import glob
import importlib
import os
import shutil
import subprocess
import sys

failures = 0


def report(ok, label, detail=""):
    global failures
    mark = "\033[1;32m[ok]  \033[0m" if ok else "\033[1;31m[FAIL]\033[0m"
    print(f"{mark} {label}" + (f": {detail}" if detail else ""))
    if not ok:
        failures += 1


def warn(label, detail=""):
    print(f"\033[1;33m[warn]\033[0m {label}" + (f": {detail}" if detail else ""))


# --- Isolation: are we inside a venv, not the system Python? -----------------
in_venv = sys.prefix != sys.base_prefix
report(in_venv, "Running inside a virtual environment", sys.prefix)
report(sys.version_info >= (3, 12), "Python >= 3.12", sys.version.split()[0])

# --- PyTorch / CUDA ------------------------------------------------------------
try:
    import torch

    report(True, "torch", f"{torch.__version__} (CUDA build {torch.version.cuda})")
    if torch.cuda.is_available():
        name = torch.cuda.get_device_name(0)
        major, minor = torch.cuda.get_device_capability(0)
        arch = f"sm_{major}{minor}"
        report(True, "CUDA GPU", f"{name}, compute capability {major}.{minor}")
        supported = torch.cuda.get_arch_list()
        report(
            arch in supported or f"compute_{major}{minor}" in supported,
            f"torch build supports {arch}",
            " ".join(supported),
        )
        x = torch.randn(1024, 1024, device="cuda")
        report(torch.isfinite(x @ x).all().item(), "GPU matmul test")
        props = torch.cuda.get_device_properties(0)
        print(f"       VRAM: {props.total_memory / 1024**3:.1f} GiB")
    else:
        warn("CUDA not available", "training will run on CPU (check the NVIDIA driver)")
except Exception as e:  # noqa: BLE001
    report(False, "torch import", repr(e))

# --- LeRobot + SO-101 dependencies ---------------------------------------------
for mod, label in [
    ("lerobot", "lerobot"),
    ("scservo_sdk", "Feetech SDK (SO-101 motors)"),
    ("serial", "pyserial"),
    ("cv2", "OpenCV (cameras)"),
    ("datasets", "datasets"),
    ("rerun", "rerun-sdk (visualization)"),
    ("pynput", "pynput (keyboard events)"),
]:
    try:
        m = importlib.import_module(mod)
        report(True, label, getattr(m, "__version__", ""))
    except Exception as e:  # noqa: BLE001
        report(False, label, repr(e))

try:
    import torchcodec  # noqa: F401
    from torchcodec.decoders import VideoDecoder  # noqa: F401

    report(True, "torchcodec (video decoding)", getattr(torchcodec, "__version__", ""))
except Exception as e:  # noqa: BLE001
    report(False, "torchcodec (video decoding)", repr(e))

# --- ffmpeg -------------------------------------------------------------------
ffmpeg = shutil.which("ffmpeg")
report(ffmpeg is not None, "ffmpeg on PATH", ffmpeg or "missing (sudo apt install ffmpeg)")
if ffmpeg:
    enc = subprocess.run([ffmpeg, "-hide_banner", "-encoders"], capture_output=True, text=True).stdout
    if "libsvtav1" in enc:
        report(True, "ffmpeg has libsvtav1 encoder")
    else:
        warn("ffmpeg lacks libsvtav1", "recording will fall back to another codec")

# --- CLI entry points -------------------------------------------------------
for exe in ["lerobot-find-port", "lerobot-setup-motors", "lerobot-calibrate",
            "lerobot-teleoperate", "lerobot-record", "lerobot-train", "hf"]:
    path = os.path.join(sys.prefix, "bin", exe)
    report(os.path.isfile(path), f"{exe}", path if os.path.isfile(path) else "not found in venv")

# --- Hardware (informational) -------------------------------------------------
ports = sorted(glob.glob("/dev/ttyACM*") + glob.glob("/dev/ttyUSB*") + glob.glob("/dev/so101_*"))
print(f"       Serial ports: {', '.join(ports) if ports else 'none (arms not plugged in?)'}")
cams = sorted(glob.glob("/dev/video*"))
print(f"       Video devices: {', '.join(cams) if cams else 'none'}")

print()
if failures:
    print(f"\033[1;31m{failures} check(s) failed.\033[0m")
    sys.exit(1)
print("\033[1;32mAll checks passed.\033[0m")
