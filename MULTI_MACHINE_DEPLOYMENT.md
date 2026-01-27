# Haas Pi USB Sync - Multi-Machine Deployment Guide

This guide covers deploying the Haas Pi USB sync system to three different Raspberry Pi devices for machines: **haas030** (lathe), **haas120**, and **haas122** (mills).

## Overview

Each Pi will:
- Run the same base system with systemd services and timers
- Connect to the same network share (//Weld-KC01/cnc programs)
- Sync to different subdirectories based on machine type
- Use machine-specific hostnames for identification

## Machine Configuration

| Machine  | Type  | Share Path |
|----------|-------|-----------|
| haas030  | Lathe | `/mnt/haasshare/Master Proven Prg/Lathe/` |
| haas120  | Mill  | `/mnt/haasshare/Master Proven Prg/Mill/120-123 new 8-22` |
| haas122  | Mill  | `/mnt/haasshare/Master Proven Prg/Mill/120-123 new 8-22` |

## Installation Steps

### 1. Prepare Each Pi

For each Pi (haas030, haas120, haas122):

1. Flash Raspberry Pi OS (Debian Trixie x64) to SD card
2. Boot and configure:
   - Set hostname: `sudo hostnamectl set-hostname haas030` (or haas120, haas122)
   - Configure WiFi: `sudo nmcli device wifi connect "SSID" password "PASSWORD"`
   - Enable SSH: `sudo systemctl enable ssh && sudo systemctl start ssh`
3. Create user `admin` if not already present
4. SSH into the Pi as `admin`

### 2. Copy Project Files

From your workstation, copy the project to each Pi:

```bash
# For haas030:
scp -r haas-pi0-usb-sync bootstrap-haaspi_l.sh configure-machine.sh admin@haas030.local:~/

# For haas120:
scp -r haas-pi0-usb-sync bootstrap-haaspi_l.sh configure-machine.sh admin@haas120.local:~/

# For haas122:
scp -r haas-pi0-usb-sync bootstrap-haaspi_l.sh configure-machine.sh admin@haas122.local:~/
```

### 3. Run Bootstrap Script

SSH into each Pi and run the bootstrap:

```bash
ssh admin@haas030.local  # (or haas120.local, haas122.local)
cd ~
chmod +x bootstrap-haaspi_l.sh configure-machine.sh
./bootstrap-haaspi_l.sh
```

The bootstrap script will:
- Install all required packages
- Create the 8GB `/piusb.bin` disk image
- Install the haas-sync script and systemd services
- Set up network share mounting
- Add helpful bash aliases
- Enable and start all services

### 4. Configure for Specific Machine

After bootstrap completes, configure for the specific machine:

```bash
# On haas030:
./configure-machine.sh haas030

# On haas120:
./configure-machine.sh haas120

# On haas122:
./configure-machine.sh haas122
```

Or manually edit `/usr/local/sbin/haas-sync`:

```bash
sudo nano /usr/local/sbin/haas-sync
```

Set these values:
```bash
# For haas030:
HAAS_HOSTNAME="haas030"
SHARE_ROOT="/mnt/haasshare/Master Proven Prg/Lathe/"

# For haas120/haas122:
HAAS_HOSTNAME="haas120"  # or "haas122"
SHARE_ROOT="/mnt/haasshare/Master Proven Prg/Mill/120-123 new 8-22"
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
| `hsync` or `haas-sync` | Manually trigger a sync |
| `status` | Show service status and recent logs |
| `off` | Safely shut down (stops services, unmounts, powers off) |
| `fix` | Repair utility (runs fsck, remounts, restarts services) |

**Note:** The standard Linux `sync` command is NOT overridden - use `hsync` or `haas-sync` instead.

## Automatic Syncing

Once configured, syncing happens automatically:

- **Every 10 minutes**: Check if network share changed, sync if needed
- **Every 1 hour**: Force full sync to capture CNC-side changes

## Verification Checklist

For each machine, verify:

- [ ] Hostname is correct: `hostname` should show `haas030`, `haas120`, or `haas122`
- [ ] USB gadget is active: `lsmod | grep g_mass_storage`
- [ ] Share is mounted: `ls /mnt/haasshare`
- [ ] Sync script has correct settings: `sudo nano /usr/local/sbin/haas-sync`
- [ ] Services are running: `systemctl list-timers | grep haas`
- [ ] Logs show successful sync: `sudo tail -n 50 /var/log/haas-sync.log`
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
sudo mount -t cifs "//Weld-KC01/cnc programs" /mnt/haasshare -o credentials=/etc/samba/credentials-haas

# Check logs
sudo journalctl -u mnt-haasshare.mount
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
sudo tail -n 100 /var/log/haas-sync.log

# Run fix utility
fix

# Manual sync with full mode
sudo /usr/local/sbin/haas-sync --full
```

## File Locations

| File/Directory | Purpose |
|----------------|---------|
| `/piusb.bin` | 8GB vfat disk image (USB drive) |
| `/mnt/piusb` | Mount point for /piusb.bin during sync |
| `/mnt/haasshare` | Mount point for network share |
| `/usr/local/sbin/haas-sync` | Main sync script (edit for machine config) |
| `/etc/samba/credentials-haas` | SMB credentials |
| `/var/log/haas-sync.log` | Sync logs |
| `/var/lib/haas-sync/` | State files (share hashes) |
| `/etc/systemd/system/haas-sync*` | Systemd service/timer units |

## Network Share Structure

```
//Weld-KC01/cnc programs/
└── Master Proven Prg/
    ├── Lathe/              # haas030 syncs here
    └── Mill/
        └── 120-123 new 8-22/  # haas120, haas122 sync here
```

## Updating the Configuration

If you need to change the share path or hostname after installation:

1. Edit the sync script:
   ```bash
   sudo nano /usr/local/sbin/haas-sync
   ```

2. Update `HAAS_HOSTNAME` and `SHARE_ROOT`

3. Reload and restart:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart haas-sync.timer
   sudo systemctl restart haas-sync-full.timer
   hsync
   ```

## Adding More Machines

To add a new machine (e.g., haas121):

1. Follow the same installation steps
2. Edit `configure-machine.sh` to add the new machine's share path
3. Run `./configure-machine.sh haas121`

Or manually edit `/usr/local/sbin/haas-sync` with the correct values.
