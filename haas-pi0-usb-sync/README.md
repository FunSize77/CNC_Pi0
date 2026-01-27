# Haas Pi Zero 2W USB Sync

Raspberry Pi Zero 2W setup to emulate a USB flash drive for HAAS CNC controllers
and keep it in sync with a network share.

## Quick Start

1. Flash Raspberry Pi OS 64-bit (Bookworm or newer) to your Pi Zero 2W
2. Copy this repository and `bootstrap-haaspi_l.sh` to the Pi
3. Run `./bootstrap-haaspi_l.sh` to automatically install everything
4. Configure for your machine: `./configure-machine.sh haas030` (or haas120, haas122)
5. The Pi will now sync with your network share automatically

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for detailed installation instructions.

**For multiple machines:** See `../MULTI_MACHINE_DEPLOYMENT.md` for deploying to haas030, haas120, and haas122.

---

This repo includes:

- **`bootstrap-haaspi_l.sh`** (in parent directory)
  Automated installation script that configures everything on a fresh Debian Trixie install.

- **`configure-machine.sh`** (in parent directory)
  Helper script to configure the Pi for specific machines (haas030, haas120, haas122).

- **`scripts/haas-sync`**
  Sync script with two modes:
  - **share mode** (default, no args): checks the network share for changes every 10 minutes and only runs a full sync if something changed.
  - **full mode** (`--full`): always runs a full sync cycle (detach USB, mount `/piusb.bin`, Unison, reattach).

- **`systemd/usb-gadget.service`**
  Loads the `g_mass_storage` gadget at boot so the Pi appears as a USB drive.

- **`systemd/haas-sync.service`** + **`systemd/haas-sync.timer`**
  Share-change-only sync every 10 minutes.

- **`systemd/haas-sync-full.service`** + **`systemd/haas-sync-full.timer`**
  Forced full sync every hour to pick up HAAS-side changes.

- **`config/g_mass_storage.conf.example`**
  Optional modprobe config for `g_mass_storage`.

- **`docs/DEPLOYMENT.md`**
  Step‑by‑step deployment instructions (both automated and manual).

## High-level behavior

- Pi boots → `usb-gadget.service` loads `g_mass_storage` and exports `/piusb.bin` as a USB mass‑storage device.
- Every 10 minutes → `haas-sync.timer` fires:
  - `haas-sync` runs in **share** mode.
  - If the network share (`SHARE_ROOT`) hash hasn’t changed → **no-op**, USB stays attached.
  - If the hash changed → full sync (detach, mount, Unison, reattach).
- Every hour → `haas-sync-full.timer` fires:
  - `haas-sync --full` always does a full sync cycle to capture any HAAS‑side writes.

Per‑Pi configuration is limited to two variables in `scripts/haas-sync`:

- `HAAS_HOSTNAME`
- `SHARE_ROOT`
