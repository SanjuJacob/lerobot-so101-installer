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

# --- Video: encode with PyAV (bundled ffmpeg), decode with TorchCodec ---------
# Recording encodes through PyAV, which ships its own ffmpeg. Decoding (training,
# replay) goes through TorchCodec, which loads the *system* ffmpeg libraries -
# that is the part that differs between Ubuntu releases, so test it for real.
ffmpeg = shutil.which("ffmpeg")
if ffmpeg:
    first = subprocess.run([ffmpeg, "-version"], capture_output=True, text=True).stdout.splitlines()
    print(f"       System {first[0] if first else 'ffmpeg'}")
else:
    warn("ffmpeg not on PATH", "sudo apt install ffmpeg")

try:
    import tempfile

    import av
    import numpy as np

    codec = "libsvtav1"
    try:
        av.codec.Codec(codec, "w")
    except Exception:  # noqa: BLE001
        codec = "libx264"
    report(True, "PyAV encoder for recording", f"av {av.__version__}, {codec}")

    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "test.mp4")
        with av.open(path, "w") as container:
            stream = container.add_stream(codec, rate=30)
            stream.width, stream.height, stream.pix_fmt = 64, 64, "yuv420p"
            for i in range(10):
                img = np.full((64, 64, 3), i * 20, dtype=np.uint8)
                for packet in stream.encode(av.VideoFrame.from_ndarray(img, format="rgb24")):
                    container.mux(packet)
            for packet in stream.encode():
                container.mux(packet)
        report(True, "Video encode test (PyAV)")

        try:
            import torchcodec
            from torchcodec.decoders import VideoDecoder

            frames = VideoDecoder(path).get_frames_in_range(0, 5)
            report(frames.data.shape[0] == 5, "Video decode test (torchcodec + system ffmpeg)",
                   getattr(torchcodec, "__version__", ""))
        except ImportError as e:
            report(False, "torchcodec import", repr(e)[:300])
        except Exception as e:  # noqa: BLE001
            report(False, "Video decode test (torchcodec + system ffmpeg)", repr(e)[:300])
            print("       -> the system ffmpeg version is not supported by this torchcodec;"
                  " see README 'Other Ubuntu versions'")
except Exception as e:  # noqa: BLE001
    report(False, "Video encode test (PyAV)", repr(e)[:300])

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
