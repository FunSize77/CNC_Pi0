# README.md

# CncPi0 – Raspberry Pi USB Wi-Fi Adapter for CNC

This project turns a Raspberry Pi Zero 2W (or similar) into a **network-synced USB stick** for CNC (and other) CNC machines.

## Quick Start

For a fresh installation on Debian Trixie x64:

1. Copy the `cnc-pi0-usb-sync` directory and `bootstrap-cncpi_l.sh` to your Pi
2. Run `./bootstrap-cncpi_l.sh` - it will automatically:
   - Install all required packages
   - Create the USB image file
   - Install the sync script and systemd services
   - Configure mount points and credentials
   - Add helpful bash aliases (sync, status, off, fix)
3. Edit `/usr/local/sbin/cnc-sync` to set your machine's hostname and share path
4. Done! The Pi will automatically sync every 10 minutes

See `cnc-pi0-usb-sync/docs/DEPLOYMENT.md` for detailed instructions.

---

## Overview

The Pi:

- Connects to your **Wi-Fi network(s)**
- Mounts a **Windows/SMB share** containing CNC programs
- Syncs that share to a local **vfat disk image** (`/piusb.bin`) using Unison + rsync
- Exposes that disk image to the CNC as a **USB flash drive** via `g_mass_storage`
- Supports **two-way sync**:
  - Changes from the network share flow down to the machine
  - Programs saved from the machine back to “USB” flow up to the network share
- Has safety logic to **protect the network share** if the USB image gets wiped or corrupted

This README gives the high-level design and the “how to use it” view. For implementation details, see:

- `README-cnc-sync.md` – scripts, services, timers, aliases
- `SAFETY-NOTES.md` – failure modes and how we avoid nuking the share

---

## 1. Architecture Overview

### Hardware

- Raspberry Pi Zero 2W (or compatible with USB OTG)
- MicroSD card (e.g. 128 GB, class 10)
- Power + USB connection to CNC CNC:
  - Pi OTG/data port → CNC USB port
- Wi-Fi network with access to your Windows file server

### OS / Software

- Raspberry Pi OS **Bookworm 64-bit Lite**
- NetworkManager (`nmcli`) for Wi-Fi
- `cifs-utils` for SMB mounting
- `unison` for two-way sync
- `rsync` and `fsck.vfat` for repair/safety
- `g_mass_storage` kernel module for USB gadget

### Key Paths

- SMB share: `//Weld-KC01/cnc programs`
- Pi mountpoint: `/mnt/cncshare`
- Local USB image: `/piusb.bin` (vfat, e.g. 8 GB)
- USB image mountpoint: `/mnt/piusb`
- CNC program root on share (example for mills 120–123):\
  `/mnt/cncshare/Master Proven Prg/Mill/120-123 new 8-22`
- Log: `/var/log/cnc-sync.log`

---

## 2. Data Flow

### Normal cycle (timer or manual `sync`):

1. **SMB share** is auto-mounted on first access via `mnt-cncshare.automount` + `mnt-cncshare.mount`.
2. `cnc-sync.service` runs `/home/admin/cnc-sync.sh`:
   - Detaches `g_mass_storage` (USB disappears from CNC briefly).
   - Mounts `/piusb.bin` → `/mnt/piusb` RW as user `admin`.
   - Measures:
     - Used space on USB vs share
     - File counts on USB vs share
   - Decides between:
     - **Two-way Unison sync** (normal), or
     - **One-way rsync SHARE → USB** (if USB looks wiped but share is full).
   - Unmounts `/mnt/piusb`.
   - Re-attaches `g_mass_storage` **RW** so CNC can read/write USB.
3. Timer repeats this periodically.

### CNC side:

- Machine sees the Pi as a USB stick:
  - Operator mounts USB in CNC control as usual.
  - Programs can be **read from** and **written to** the USB device.
- On the next sync:
  - New/changed programs on CNC USB are pulled into the network share.
  - New/changed programs on the network share are pushed down to the USB image.

---

## 3. Two-Way Sync + Safety

The design is **two-way**, but with guard rails:

- **Normal case**:
  - Unison runs in **two-way** mode between `/mnt/piusb` and the share root.
  - `-maxdelete 100` limits how much can be deleted per run.
- **Protection case** (USB looks empty, share is “full”):
  - If USB used space `< 3.5 GB` *and* the share has `> 50` files,\
    `cnc-sync.sh` assumes **USB is the problem** and:
    - Skips two-way Unison.
    - Runs `rsync -a --delete SHARE → USB` to **rebuild the USB image from the share**.
    - Never deletes anything from the network share in that mode.

See `SAFETY-NOTES.md` for deeper detail.

---

## 4. Usage – Operator View

On the CNC control:

1. Plug Pi OTG USB into the CNC USB port.
2. Power Pi (from CNC USB or separate PSU).
3. On CNC:
   - `LIST PROGRAM`
   - Select **USB DEVICE**
   - Press `F1` → **MOUNT**

Programs on the share path (e.g. `.../Mill/120-123 new 8-22`) appear on the CNC USB.

To get new programs from the network → CNC:

- Save them to the configured share path.
- Wait for the next timer sync, or ask someone to run `sync` on the Pi.
- Refresh or remount the USB list on the CNC.

To push proven programs from CNC → network:

- Save/copy the program from CNC control to USB.
- Wait for next timer or manual `sync`.
- Program will show up in the network share folder.

Operators never need to touch SSH, Unison, or anything on the Pi.

---

## 5. Usage – Admin Commands on the Pi

All run as user `admin` via the helper aliases/functions in `~/.bashrc`:

- **Manual sync (no password)**:

  ```bash
  sync
  ```

  Triggers `cnc-sync.service` once.

- **Check status**:

  ```bash
  status
  ```

  Shows:

  - `systemctl status` for `cnc-sync.service` and `cnc-sync.timer`
  - Last 20 lines of `/var/log/cnc-sync.log`

- **Emergency repair** (“fix the USB pipeline”):

  ```bash
  fix
  ```

  Does:

  - Ensures automount is enabled and `/mnt/cncshare` is reachable.
  - Stops `cnc-sync` service and timer.
  - Detaches `g_mass_storage`, unmounts `/mnt/piusb`.
  - Runs `fsck.vfat -a /piusb.bin`.
  - Re-attaches `g_mass_storage` RW.
  - Restarts the timer.
  - Forces one sync.

- **Shutdown Pi safely**:

  ```bash
  off
  ```

  Does:

  - Stops timer and service.
  - Detaches USB gadget.
  - Unmounts `/mnt/piusb` and `/mnt/cncshare`.
  - Calls `shutdown -h now`.

---

## 6. Cloning to Other Machines

Recommended workflow:

1. Treat CNC120 (known-good Pi) as **golden image**.
2. Use Win32 Disk Imager (or `dd`) to read its SD → `CNC120-golden.img`.
3. Write that image to other SD cards.
4. On each new Pi:
   - Change hostname: `CNC121`, `CNC122`, `CNC123`, `CNC030`, `CNC031`.
   - Edit `/etc/hosts` to match hostname.
   - Adjust `SHARE_ROOT` in `/home/admin/cnc-sync.sh`:
     - Mills (120–123): same Mill root.
     - Lathes (030/031): point to the lathe programs folder.
   - Run:
     ```bash
     ls /mnt/cncshare
     sync
     status
     ```
   - Verify on the CNC control that USB programs match expectation.

---

## 7. Files of Interest

- Top-level:

  - `README.md` (this file)
  - `README-cnc-sync.md` – deeper dive on services, scripts, aliases
  - `SAFETY-NOTES.md` – sync/deletion safety, failure modes

- On the Pi filesystem:

  - `/home/admin/cnc-sync.sh`
  - `/etc/systemd/system/cnc-sync.service`
  - `/etc/systemd/system/cnc-sync.timer`
  - `/etc/systemd/system/mnt-cncshare.mount`
  - `/etc/systemd/system/mnt-cncshare.automount`
  - `/etc/samba/credentials-cnc`
  - `/var/log/cnc-sync.log`
  - `~/.bashrc` (contains `sync`, `status`, `off`, `fix` helpers)

---

# README-cnc-sync.md

# cnc-sync – SMB ↔ USB Image Sync Engine

This document describes the **sync pipeline** that keeps a CNC program share and the Pi’s USB image in sync and exposes it to the CNC as a USB drive.

It covers:

- The main sync script (`cnc-sync.sh`)
- Systemd service + timer
- SMB automount
- Helper aliases/functions

---

## 1. Main Script: `/home/admin/cnc-sync.sh`

### Purpose

`cnc-sync.sh` is a **one-shot** script that:

1. Ensures the SMB share is available at `/mnt/cncshare`.
2. Detaches the USB gadget from the CNC.
3. Mounts the local USB image `/piusb.bin` at `/mnt/piusb` RW.
4. Applies **safe 2-way sync logic** between:
   - USB side: `/mnt/piusb`
   - Network side: `$SHARE_ROOT` on `/mnt/cncshare`
5. Unmounts `/mnt/piusb`.
6. Reattaches the USB gadget **RW** for the CNC.

### Key Variables

```bash
LOG=/var/log/cnc-sync.log

USB_IMG="/piusb.bin"
USB_MNT="/mnt/piusb"

# Example for CNC120–123 mill
SHARE_ROOT="/mnt/cncshare/Master Proven Prg/Mill/120-123 new 8-22"

ADMIN_UID=1000
ADMIN_GID=1000

MIN_USB_BYTES=3500000000   # 3.5 GB; below this, USB is treated as "possibly wiped"
MIN_SHARE_FILES=50         # if share has at least this many files, assume it's real
```

To adapt for other machines:

- For mills 120–123: keep `SHARE_ROOT` as above.
- For lathes 030/031: change `SHARE_ROOT` to the lathe programs folder.

### High-Level Flow

1. **Sanity checks:**

   - `/mnt/cncshare` must be mounted (handled by systemd automount).

2. **Detach gadget and mount USB image:**

   - `modprobe -r g_mass_storage` if loaded.
   - `mount -o loop,rw,uid=1000,gid=1000,umask=002 /piusb.bin /mnt/piusb`

3. **Measure size and file counts:**

   - `usb_used`, `share_used` via `df -B1`
   - `usb_files`, `share_files` via `find + wc -l`

4. **Safety decision:**

   ```bash
   if usb_used < MIN_USB_BYTES && share_files > MIN_SHARE_FILES:
       # USB is suspiciously empty, share is not → protect share
       rsync -a --delete SHARE_ROOT/ → USB_MNT/
   else
       # Normal case → run two-way Unison with deletion cap
       unison USB_MNT SHARE_ROOT -auto -batch -maxdelete 100 -perms 0
   fi
   ```

5. **Unmount and reattach gadget:**

   - `umount /mnt/piusb`
   - `modprobe g_mass_storage file=/piusb.bin stall=0 removable=1`\
     (no `ro=1` → gadget is RW from CNC).

### Logging

All major steps log to `/var/log/cnc-sync.log`, e.g.:

```text
[2025-11-20T08:53:06-06:00] cnc-sync: start
[2025-11-20T08:53:06-06:00] cnc-sync: detaching g_mass_storage
[2025-11-20T08:53:06-06:00] cnc-sync: mounting /piusb.bin to /mnt/piusb (rw,uid=1000,gid=1000,umask=002)
[2025-11-20T08:53:06-06:00] cnc-sync: USB used=xxxxB, files=yy; SHARE used=zzzzB, files=nn
[2025-11-20T08:53:06-06:00] cnc-sync: starting Unison two-way sync with delete limit
[2025-11-20T08:53:34-06:00] cnc-sync: Unison complete
[2025-11-20T08:53:34-06:00] cnc-sync: unmounting /mnt/piusb
[2025-11-20T08:53:34-06:00] cnc-sync: reattaching g_mass_storage (RW)
[2025-11-20T08:53:34-06:00] cnc-sync: done
```

---

## 2. Systemd Units

### 2.1. `cnc-sync.service`

File: `/etc/systemd/system/cnc-sync.service`

```ini
[Unit]
Description=Sync SMB share to local USB image and attach RO (g_mass_storage)
After=mnt-cncshare.automount
Wants=mnt-cncshare.automount

[Service]
Type=oneshot
User=root
Group=root
ExecStart=/usr/bin/flock -n /run/lock/cnc-sync.lock /home/admin/cnc-sync.sh
Nice=10

[Install]
WantedBy=multi-user.target
```

Notes:

- `Type=oneshot`: runs once per invocation, no daemon.
- `flock` prevents overlapping runs.
- `After/Wants` ensure the automount is active before syncing.

### 2.2. `cnc-sync.timer`

File: `/etc/systemd/system/cnc-sync.timer`

```ini
[Unit]
Description=Periodic sync of CNC SMB share to USB image

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=cnc-sync.service

[Install]
WantedBy=timers.target
```

Behavior:

- Waits 2 minutes after boot.
- Then runs `cnc-sync.service` every 5 minutes.
- Can be enabled/disabled with:
  ```bash
  sudo systemctl enable cnc-sync.timer
  sudo systemctl disable cnc-sync.timer
  ```

---

## 3. SMB Automount

### 3.1. `mnt-cncshare.mount`

File: `/etc/systemd/system/mnt-cncshare.mount`

```ini
[Unit]
Description=SMB mount for CNC share (Weld-KC01\cnc programs)
After=network-online.target
Wants=network-online.target

[Mount]
What=//Weld-KC01/cnc programs
Where=/mnt/cncshare
Type=cifs
Options=credentials=/etc/samba/credentials-cnc,iocharset=utf8,vers=3.0,sec=ntlmssp,noperm,uid=1000,gid=1000,file_mode=0775,dir_mode=0775

[Install]
WantedBy=multi-user.target
```

### 3.2. `mnt-cncshare.automount`

File: `/etc/systemd/system/mnt-cncshare.automount`

```ini
[Unit]
Description=Automount CNC SMB share at /mnt/cncshare

[Automount]
Where=/mnt/cncshare

[Install]
WantedBy=multi-user.target
```

### 3.3. Credentials File

File: `/etc/samba/credentials-cnc`

```text
username=SCAN4
password=YOUR_PASSWORD_HERE
domain=weldracing.local
```

Permissions:

```bash
sudo chmod 600 /etc/samba/credentials-cnc
```

---

## 4. Aliases and Helper Functions (`~/.bashrc`)

These live in `admin`’s `~/.bashrc` and are part of the standard setup.

### 4.1. Sync aliases

```bash
# Run a sync (no-password sudo already configured for cnc-sync)
alias cnc-sync='sudo systemctl start cnc-sync.service'
alias sync='cnc-sync'
alias hsync='cnc-sync'
```

### 4.2. Status function

```bash
status() {
  echo "=== cnc-sync.service ==="
  sudo systemctl status cnc-sync.service --no-pager
  echo
  echo "=== cnc-sync.timer ==="
  sudo systemctl status cnc-sync.timer --no-pager
  echo
  echo "=== last 20 lines of /var/log/cnc-sync.log ==="
  sudo tail -n 20 /var/log/cnc-sync.log
}
```

### 4.3. Shutdown function (`off`)

```bash
off() {
  echo "[off] Stopping cnc-sync timer and service..."
  sudo systemctl stop cnc-sync.timer 2>/dev/null || true
  sudo systemctl stop cnc-sync.service 2>/dev/null || true

  echo "[off] Detaching USB gadget and unmounting filesystems..."
  sudo modprobe -r g_mass_storage 2>/dev/null || true
  sudo umount /mnt/piusb 2>/dev/null || true
  sudo umount /mnt/cncshare 2>/dev/null || true

  echo "[off] Shutting down Pi now..."
  sudo shutdown -h now
}
```

### 4.4. Repair function (`fix`)

```bash
fix() {
  echo "[fix] Checking CNC Pi USB setup..."

  if [ ! -f /etc/samba/credentials-cnc ]; then
    echo "[fix] ERROR: /etc/samba/credentials-cnc not found."
    return 1
  fi

  if [ ! -f /piusb.bin ]; then
    echo "[fix] ERROR: /piusb.bin not found."
    return 1
  fi

  echo "[fix] Reloading systemd units and ensuring automount is enabled..."
  sudo systemctl daemon-reload
  sudo systemctl enable mnt-cncshare.automount >/dev/null 2>&1 || true
  sudo systemctl start mnt-cncshare.automount >/dev/null 2>&1 || true

  echo "[fix] Forcing SMB mount (ls /mnt/cncshare)..."
  if ! ls /mnt/cncshare >/dev/null 2>&1; then
    echo "[fix] ERROR: Unable to list /mnt/cncshare."
    return 1
  fi

  echo "[fix] Stopping cnc-sync timer and service..."
  sudo systemctl stop cnc-sync.timer 2>/dev/null || true
  sudo systemctl stop cnc-sync.service 2>/dev/null || true

  echo "[fix] Detaching g_mass_storage and unmounting /mnt/piusb..."
  sudo modprobe -r g_mass_storage 2>/dev/null || true
  sudo umount /mnt/piusb 2>/dev/null || true

  echo "[fix] Running fsck.vfat on /piusb.bin (auto-fix)..."
  sudo fsck.vfat -a /piusb.bin

  echo "[fix] Reattaching g_mass_storage (RW)..."
  sudo modprobe g_mass_storage file=/piusb.bin stall=0 removable=1

  echo "[fix] Restarting cnc-sync.timer..."
  sudo systemctl start cnc-sync.timer 2>/dev/null || true

  echo "[fix] Forcing one cnc-sync.service run..."
  sudo systemctl start cnc-sync.service

  echo "[fix] Done. Use 'status' to verify recent sync logs."
}
```

---

## 5. Wi-Fi Configuration (Primary + Backup)

Managed by NetworkManager (`nmcli`).

### Primary connection

Detected as:

```bash
nmcli -t -f NAME,TYPE,DEVICE connection show
# example: preconfigured:802-11-wireless:wlan0
```

### Backup network (example: SSID `WRAP`)

Create manually (even if out of range):

```bash
sudo nmcli connection add type wifi ifname wlan0 con-name "WRAP" ssid "WRAP"
sudo nmcli connection modify "WRAP" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "MWr@c1ng$"
sudo nmcli connection modify "WRAP" connection.autoconnect yes
```

Set priorities:

```bash
sudo nmcli connection modify "preconfigured" connection.autoconnect-priority 100
sudo nmcli connection modify "WRAP"         connection.autoconnect-priority 10
```

NetworkManager will prefer `preconfigured` when both are in range, and fall back to `WRAP` when needed.

---

## 6. Cloning Checklist (Per New Pi)

1. Write `CNC120-golden.img` to SD.
2. Boot Pi, SSH in as `admin`.
3. Change hostname:
   ```bash
   sudo hostnamectl set-hostname CNC121   # adjust per machine
   sudo nano /etc/hosts                    # update 127.0.1.1 line
   ```
4. If needed, change `SHARE_ROOT` in `/home/admin/cnc-sync.sh`.
5. Test:
   ```bash
   ls /mnt/cncshare
   sync
   status
   ```
6. Verify on CNC control: USB contents match expectations.

---

# SAFETY-NOTES.md

# Safety Notes – Protecting the Network Share and USB Image

This file documents the **failure modes** we care about and how the current setup is designed to avoid catastrophic data loss (especially on the network share).

The main problem we solved:

> If the USB image (`/piusb.bin`) ever gets wiped or corrupted, we **must not let Unison delete all the files on the network share as “sync cleanup.”**

---

## 1. Primary Risks

### Risk 1 – Empty / Corrupt USB Image

Scenarios:

- SD card / filesystem corruption.
- `mkfs` or a bad script accidentally recreates the filesystem on `/piusb.bin`.
- `fsck.vfat` repairs by nuking large parts of the filesystem.
- A fresh card gets used without being properly seeded from the share.

Result without protection:

- Unison sees **USB side empty**, **share side full**.
- It thinks: “User deleted everything on USB, so I should propagate deletions.”
- It then tries to delete all files on the share to “match” the USB state.

### Risk 2 – Unbounded Deletion in Normal 2-Way Sync

Even if both sides are generally healthy:

- A path misconfiguration or someone pointing to the wrong directory could lead to Unison attempting to delete a large number of files.
- If Unison runs unconstrained, it might happily delete thousands of files before anyone notices.

---

## 2. Safety Mechanisms

### 2.1. Heuristic Guard – “USB Looks Wiped” Detection

In `/home/admin/cnc-sync.sh`:

```bash
MIN_USB_BYTES=3500000000   # 3.5 GB
MIN_SHARE_FILES=50         # if share has at least this many files, assume it's real
```

After mounting `/piusb.bin`:

```bash
usb_used=$(df -B1 "$USB_MNT" | awk 'NR==2 {print $3}')
share_used=$(df -B1 "$SHARE_ROOT" | awk 'NR==2 {print $3}')
usb_files=$(find "$USB_MNT" -mindepth 1 -type f 2>/dev/null | wc -l || echo 0)
share_files=$(find "$SHARE_ROOT" -mindepth 1 -type f 2>/dev/null | wc -l || echo 0)

log "cnc-sync: USB used=${usb_used}B, files=${usb_files}; SHARE used=${share_used}B, files=${share_files}"

if [ "$usb_used" -lt "$MIN_USB_BYTES" ] && [ "$share_files" -gt "$MIN_SHARE_FILES" ]; then
  log "cnc-sync: WARNING: USB side looks small/empty; protecting network share."
  log "cnc-sync: Rebuilding USB image from network share via rsync (share -> USB only)."

  rsync -a --delete "$SHARE_ROOT"/ "$USB_MNT"/
else
  # Normal two-way Unison
  unison "$USB_MNT" "$SHARE_ROOT" -auto -batch -maxdelete 100 -perms 0
fi
```

Interpretation:

- If USB has **less than 3.5 GB used** and the share has **more than 50 files**, we treat USB as **unreliable** and assume the share is canonical.
- In that case, we do **one-way repair**:
  - `rsync -a --delete SHARE → USB`
  - This reconstructs USB from the share.
  - **No deletions occur on the share.**

You can tune:

- `MIN_USB_BYTES` upward or downward as your image size and usage pattern dictate.
- `MIN_SHARE_FILES` based on how many files “normal” looks like in your environment.

The goal is to clearly differentiate:

- “USB truly changed” vs
- “USB just came up empty and is lying to us.”

### 2.2. Bounded Deletion in Normal Unison Runs

Unison is invoked with:

```bash
unison "$USB_MNT" "$SHARE_ROOT" -auto -batch -maxdelete 100 -perms 0
```

Important bits:

- `-auto -batch`: non-interactive, suitable for a systemd service.
- `-maxdelete 100`: Unison refuses to proceed if more than 100 deletions would occur in a single sync.

So even if:

- Someone messes up a path,
- Or the USB side looks weird but doesn’t trigger the heuristic guard,

Unison cannot silently delete more than 100 items in one pass.

If it hits that limit, the run fails, logs an error, and the service exits. It does **not** apply the deletions.

---

## 3. Two-Way Sync vs. One-Way Repair

### Normal Operation – Two-Way

Conditions:

- USB used ≥ `MIN_USB_BYTES`, or
- Share has ≤ `MIN_SHARE_FILES` (not enough data to assume it’s canonical).

Behavior:

- Two-way Unison:
  - New/changed files on USB (CNC) propagate to the share.
  - New/changed files on share propagate to USB.
  - Small-scale deletions can propagate in either direction, subject to `-maxdelete 100`.

This is the **steady-state** behavior when everything is healthy.

### Repair Mode – Share is Canonical

Conditions:

- USB used < `MIN_USB_BYTES`
- Share files > `MIN_SHARE_FILES`

Behavior:

- USB is treated as “possibly wiped or corrupt.”
- Unison is **not** run.
- `rsync -a --delete SHARE → USB` is used:
  - Rebuilds `/piusb.bin` contents from the network share.
  - Deletes files from USB that do not exist on the share.
  - **Never deletes from the share.**

After this repair, subsequent syncs go back to normal two-way behavior.

---

## 4. Interaction with `fix` and `off`

### 4.1. `off`

`off` is a **safe shutdown** helper:

- Stops `cnc-sync.timer` and `cnc-sync.service`
- Detaches `g_mass_storage`
- Unmounts `/mnt/piusb` and `/mnt/cncshare`
- Shuts the Pi down via `shutdown -h now`

This ensures no sync is in progress, nothing is mounted, and the Pi powers off cleanly. It does **not** itself modify contents of `/piusb.bin` or the share.

### 4.2. `fix`

`fix` is the **“USB chain repair”** helper:

1. Ensures:
   - `/etc/samba/credentials-cnc` exists
   - `/piusb.bin` exists
2. Reloads systemd units and ensures `mnt-cncshare.automount` is enabled.
3. Forces the SMB share to mount (by `ls /mnt/cncshare`).
4. Stops `cnc-sync.timer` and `cnc-sync.service`.
5. Detaches gadget and unmounts `/mnt/piusb`.
6. Runs:
   ```bash
   fsck.vfat -a /piusb.bin
   ```
   This attempts automatic repair of the vfat filesystem.
7. Reattaches `g_mass_storage` **RW**:
   ```bash
   sudo modprobe g_mass_storage file=/piusb.bin stall=0 removable=1
   ```
8. Restarts the timer and forces one immediate `cnc-sync.service` run.

Important:

- If `fsck.vfat` has to do heavy repairs and “shrinks” or wipes parts of the USB filesystem, the **next** `cnc-sync` run will see a “small/empty USB” and fall into the **repair-from-share** path (rsync SHARE → USB).
- That is by design: after filesystem repair, we treat the network share as canonical to avoid sending bogus deletions upstream.

---

## 5. What NOT to Do

To avoid bypassing the safety logic:

1. **Don’t run Unison manually** against the raw SMB and USB paths without the same options:
   - No interactive manual `unison /mnt/piusb /mnt/cncshare/...` without `-maxdelete` and `-perms 0`.
2. **Don’t mount ****\`\`**** and start deleting large swaths manually**, then let a sync run, unless you actually intend to propagate those deletions.
3. **Don’t recreate ****\`\`**** from scratch** without immediately seeding it from the share:
   - If you must recreate it:
     - `mkfs.vfat /piusb.bin`
     - Manually run a **one-way seed** from share → USB (rsync), or just run `sync` and let the guard detect and repair.
4. **Don’t point ****\`\`**** at the wrong directory**:
   - Double-check that `SHARE_ROOT` for each Pi points to the correct folder (mill vs lathe).
   - A mis-pointed `SHARE_ROOT` with lots of files can confuse the heuristic.

---

## 6. Recovery Scenarios

### Scenario A – SD / USB image corrupted, share still good

Symptoms:

- `fix` reports heavy `fsck` activity.
- Next `sync` logs:
  - `WARNING: USB side looks small/empty; protecting network share.`
  - `Rebuilding USB image from network share via rsync`

Action:

- Let `cnc-sync` complete.
- Confirm:
  - `status` shows successful sync.
  - CNC USB sees expected files.
- No action needed on the share; it was never touched.

### Scenario B – Unison hits `-maxdelete` limit

Symptoms:

- `status` shows `cnc-sync.service` failed.
- Log shows Unison complaining about exceeding `-maxdelete 100`.

Action:

- Do **not** blindly increase `-maxdelete`.
- Investigate:
  - Is `SHARE_ROOT` pointing somewhere else than expected?
  - Did someone manually purge USB or share?
- Fix the underlying path / contents.
- Rerun `sync`.

### Scenario C – Share actually needs a mass delete

If you really want to delete a ton of files across both USB and share:

- Do it **from the share** deliberately (with backups).
- Temporarily bump `-maxdelete` in `cnc-sync.sh` (with eyes open).
- Run `sync` and verify.
- Immediately restore a reasonable `-maxdelete` (e.g. 100).

---

## 7. Tuning Parameters

You can adjust:

- `MIN_USB_BYTES`:
  - Higher: more aggressive in assuming “USB is wiped” → more often rebuild USB from share.
  - Lower: more conservative → riskier if USB can be truly wiped.
- `MIN_SHARE_FILES`:
  - Higher: require more files before trusting the share as canonical.
  - Lower: treat smaller share directories as “real.”
- `-maxdelete`:
  - Lower: safer, but might block legitimate operations that really delete >N files.
  - Higher: riskier if something goes sideways.

For a typical CNC program tree, `3.5 GB` and `50 files` with `-maxdelete 100` is a sane starting point.

---

In short: the current design assumes:

- The **network share** is the source of truth when USB looks obviously wrong,
- Unison is allowed to do **two-way** sync, but on a **short leash** (`-maxdelete`),
- And `fix` correctly integrates with this by repairing the filesystem, then letting the guard + sync logic do their job.

