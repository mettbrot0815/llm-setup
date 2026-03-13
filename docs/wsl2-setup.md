# WSL2 Setup Guide

This is the primary target environment. Here's exactly what you need before running the installer.

---

## 1. Install WSL2

Open **PowerShell as Administrator** and run:

```powershell
wsl --install
```

Reboot when prompted. This installs WSL2 with Ubuntu by default.

If you already have WSL1, upgrade:
```powershell
wsl --set-default-version 2
wsl --set-version Ubuntu 2
```

---

## 2. Install NVIDIA drivers (Windows side)

Install the latest **Game Ready** or **Studio** driver from:
https://www.nvidia.com/drivers

> ⚠️ Do **not** install CUDA inside WSL2 manually. The Windows driver ships a CUDA stub — the installer handles the rest.

Verify inside WSL2 after driver install:
```bash
nvidia-smi
```

You should see your GPU listed. If not, reboot Windows.

---

## 3. Set up Ubuntu

Launch **Ubuntu** from the Start Menu and create your user account.

Update packages:
```bash
sudo apt update && sudo apt upgrade -y
```

---

## 4. Run the installer

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mettbrot0815/llm-setup/main/install.sh)
```

The installer detects WSL2 automatically and applies the correct CUDA paths (`/usr/lib/wsl/lib`).

---

## WSL2-specific notes

### GPU access
WSL2 exposes the GPU via `/usr/lib/wsl/lib`. The installer pins this path first in `LD_LIBRARY_PATH` so Ollama always finds CUDA.

### Memory
WSL2 by default uses 50% of host RAM. To increase it, create or edit `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
memory=12GB
processors=8
gpuSupport=true
```

Then restart WSL:
```powershell
wsl --shutdown
```

### Networking

### File access
Your Windows files are at `/mnt/c/Users/<YourName>/`. The `mcp-filesystem` bridge is configured to allow access to your home directory by default. Edit `~/.config/llm-setup/mcp.conf` to add more paths.

---

## Common WSL2 issues

**`nvidia-smi` not found inside WSL2**
- Make sure you're on WSL2 (not WSL1): `wsl --list --verbose`
- Update your Windows NVIDIA driver to a version that supports WSL2 (any driver from 2021+)

**Ollama loads model on CPU despite having GPU**
```bash
fix-gpu
```
This patches the Ollama systemd service to force `OLLAMA_NUM_GPU=99`.

**Out of memory errors**
Increase WSL2 memory via `.wslconfig` (see above) or switch to a smaller model:
```bash
llm-switch
```
