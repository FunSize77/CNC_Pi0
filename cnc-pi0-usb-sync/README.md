# CNC Pi Zero 2W USB Sync

Raspberry Pi Zero 2W setup to emulate a USB flash drive for CNC controllers
and keep it in sync with a network share.

## Quick Start

1. Flash Raspberry Pi OS 64-bit (Bookworm or newer) to your Pi Zero 2W
2. Copy this repository and `bootstrap-cncpi_l.sh` to the Pi
3. Run `./bootstrap-cncpi_l.sh` to automatically install everything
4. Configure for your machine: `./configure-machine.sh "$(hostname)" /mnt/cncshare/programs`
5. The Pi will now sync with your network share automatically

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for detailed installation instructions.

**For multiple machines:** See `../MULTI_MACHINE_DEPLOYMENT.md` for deploying to multiple CNC machines.

---

This repo includes:

- **`bootstrap-cncpi_l.sh`** (in parent directory)
  Automated installation script that configures everything on a fresh Debian Trixie install.

- **`configure-machine.sh`** (in parent directory)
  Helper script to configure the Pi hostname and CNC program share path.

- **`scripts/cnc-sync`**
  Sync script with two modes:
  - **share mode** (default, no args): checks the network share for changes every 10 minutes and only runs a full sync if something changed.
  - **full mode** (`--full`): always runs a full sync cycle (detach USB, mount `/piusb.bin`, Unison, reattach).

- **`systemd/usb-gadget.service`**
  Loads the `g_mass_storage` gadget at boot so the Pi appears as a USB drive.

- **`systemd/cnc-sync.service`** + **`systemd/cnc-sync.timer`**
  Share-change-only sync every 10 minutes.

- **`systemd/cnc-sync-full.service`** + **`systemd/cnc-sync-full.timer`**
  Forced full sync every hour to pick up CNC-side changes.

- **`config/g_mass_storage.conf.example`**
  Optional modprobe config for `g_mass_storage`.

- **`docs/DEPLOYMENT.md`**
  Step‑by‑step deployment instructions (both automated and manual).

## High-level behavior

- Pi boots → `usb-gadget.service` loads `g_mass_storage` and exports `/piusb.bin` as a USB mass‑storage device.
- Every 10 minutes → `cnc-sync.timer` fires:
  - `cnc-sync` runs in **share** mode.
  - If the network share (`SHARE_ROOT`) hash hasn’t changed → **no-op**, USB stays attached.
  - If the hash changed → full sync (detach, mount, Unison, reattach).
- Every hour → `cnc-sync-full.timer` fires:
  - `cnc-sync --full` always does a full sync cycle to capture any CNC‑side writes.

Per‑Pi configuration is limited to two variables in `scripts/cnc-sync`:

- `CNC_HOSTNAME`
- `SHARE_ROOT`
