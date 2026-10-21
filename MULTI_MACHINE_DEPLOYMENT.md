# CNC Pi USB Sync - Multi-Machine Deployment Guide

This guide covers deploying the CNC Pi USB sync system to three different Raspberry Pi devices for machines: **cnc030** (lathe), **cnc120**, and **cnc122** (mills).

## Overview

Each Pi will:
- Run the same base system with systemd services and timers
- Connect to the same network share (//Weld-KC01/cnc programs)
- Sync to different subdirectories based on machine type
- Use machine-specific hostnames for identification

## Machine Configuration

| Machine  | Type  | Share Path |
|----------|-------|-----------|
| cnc030  | Lathe | `/mnt/cncshare/Master Proven Prg/Lathe/` |
| cnc120  | Mill  | `/mnt/cncshare/Master Proven Prg/Mill/120-123 new 8-22` |
| cnc122  | Mill  | `/mnt/cncshare/Master Proven Prg/Mill/120-123 new 8-22` |

## Installation Steps

### 1. Prepare Each Pi

For each Pi (cnc030, cnc120, cnc122):

1. Flash Raspberry Pi OS 64-bit (Bookworm or newer) to SD card
2. Boot and configure:
   - Set hostname: `sudo hostnamectl set-hostname cnc030` (or cnc120, cnc122)
   - Configure WiFi: `sudo nmcli device wifi connect "SSID" password "PASSWORD"`
   - Enable SSH: `sudo systemctl enable ssh && sudo systemctl start ssh`
3. Create user `admin` if not already present
4. SSH into the Pi as `admin`

### 2. Copy Project Files

From your workstation, copy the project to each Pi:

```bash
# For cnc030:
scp -r cnc-pi0-usb-sync bootstrap-cncpi_l.sh configure-machine.sh admin@cnc030.local:~/

# For cnc120:
scp -r cnc-pi0-usb-sync bootstrap-cncpi_l.sh configure-machine.sh admin@cnc120.local:~/

# For cnc122:
scp -r cnc-pi0-usb-sync bootstrap-cncpi_l.sh configure-machine.sh admin@cnc122.local:~/
```

### 3. Run Bootstrap Script

SSH into each Pi and run the bootstrap:

```bash
ssh admin@cnc030.local  # (or cnc120.local, cnc122.local)
cd ~
chmod +x bootstrap-cncpi_l.sh configure-machine.sh
./bootstrap-cncpi_l.sh
```

The bootstrap script will:
- Install all required packages
- Create the 8GB `/piusb.bin` disk image
- Install the cnc-sync script and systemd services
- Set up network share mounting
- Add helpful bash aliases
- Enable and start all services

### 4. Configure for Specific Machine

After bootstrap completes, configure for the specific machine:

```bash
# On cnc030:
./configure-machine.sh cnc030

# On cnc120:
./configure-machine.sh cnc120

# On cnc122:
./configure-machine.sh cnc122
```

Or manually edit `/usr/local/sbin/cnc-sync`:

```bash
sudo nano /usr/local/sbin/cnc-sync
```

Set these values:
```bash
# For cnc030:
CNC_HOSTNAME="cnc030"
SHARE_ROOT="/mnt/cncshare/Master Proven Prg/Lathe/"

# For cnc120/cnc122:
CNC_HOSTNAME="cnc120"  # or "cnc122"
SHARE_ROOT="/mnt/cncshare/Master Proven Prg/Mill/120-123 new 8-22"
```

### 5. Test the Configuration

```bash
# Reload systemd
sudo systemctl daemon-reload

# Run a manual sync
hsync

# Check status
status
```

## Usage Commands

These aliases are available after bootstrap (added to `~/.bashrc`):

| Command | Description |
|---------|-------------|
| `hsync` or `cnc-sync` | Manually trigger a sync |
| `status` | Show service status and recent logs |
| `off` | Safely shut down (stops services, unmounts, powers off) |
| `fix` | Repair utility (runs fsck, remounts, restarts services) |

**Note:** The standard Linux `sync` command is NOT overridden - use `hsync` or `cnc-sync` instead.

## Automatic Syncing

Once configured, syncing happens automatically:

- **Every 10 minutes**: Check if network share changed, sync if needed
- **Every 1 hour**: Force full sync to capture CNC-side changes

## Verification Checklist

For each machine, verify:

- [ ] Hostname is correct: `hostname` should show `cnc030`, `cnc120`, or `cnc122`
- [ ] USB gadget is active: `lsmod | grep g_mass_storage`
- [ ] Share is mounted: `ls /mnt/cncshare`
- [ ] Sync script has correct settings: `sudo nano /usr/local/sbin/cnc-sync`
- [ ] Services are running: `systemctl list-timers | grep cnc`
- [ ] Logs show successful sync: `sudo tail -n 50 /var/log/cnc-sync.log`
- [ ] CNC machine can see USB device

## Troubleshooting

### Pi not visible on network
```bash
# Check WiFi connection
nmcli device status

# Reconnect if needed
sudo nmcli device wifi connect "SSID" password "PASSWORD"
```

### Share not mounting
```bash
# Test credentials
sudo mount -t cifs "//Weld-KC01/cnc programs" /mnt/cncshare -o credentials=/etc/samba/credentials-cnc

# Check logs
sudo journalctl -u mnt-cncshare.mount
```

### USB not appearing on CNC
```bash
# Check if gadget is loaded
lsmod | grep g_mass_storage

# Restart USB gadget
sudo systemctl restart usb-gadget.service

# Check kernel messages
sudo dmesg | tail -n 50
```

### Sync errors
```bash
# View detailed logs
sudo tail -n 100 /var/log/cnc-sync.log

# Run fix utility
fix

# Manual sync with full mode
sudo /usr/local/sbin/cnc-sync --full
```

## File Locations

| File/Directory | Purpose |
|----------------|---------|
| `/piusb.bin` | 8GB vfat disk image (USB drive) |
| `/mnt/piusb` | Mount point for /piusb.bin during sync |
| `/mnt/cncshare` | Mount point for network share |
| `/usr/local/sbin/cnc-sync` | Main sync script (edit for machine config) |
| `/etc/samba/credentials-cnc` | SMB credentials |
| `/var/log/cnc-sync.log` | Sync logs |
| `/var/lib/cnc-sync/` | State files (share hashes) |
| `/etc/systemd/system/cnc-sync*` | Systemd service/timer units |

## Network Share Structure

```
//Weld-KC01/cnc programs/
└── Master Proven Prg/
    ├── Lathe/              # cnc030 syncs here
    └── Mill/
        └── 120-123 new 8-22/  # cnc120, cnc122 sync here
```

## Updating the Configuration

If you need to change the share path or hostname after installation:

1. Edit the sync script:
   ```bash
   sudo nano /usr/local/sbin/cnc-sync
   ```

2. Update `CNC_HOSTNAME` and `SHARE_ROOT`

3. Reload and restart:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart cnc-sync.timer
   sudo systemctl restart cnc-sync-full.timer
   hsync
   ```

## Adding More Machines

To add a new machine (e.g., cnc121):

1. Follow the same installation steps
2. Edit `configure-machine.sh` to add the new machine's share path
3. Run `./configure-machine.sh cnc121`

Or manually edit `/usr/local/sbin/cnc-sync` with the correct values.
