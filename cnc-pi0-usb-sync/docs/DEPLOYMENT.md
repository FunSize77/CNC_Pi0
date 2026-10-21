# Deployment – CNC Pi Zero 2W USB Sync

This describes how to deploy the USB gadget + sync services on each Pi Zero 2W.

## Quick Start (Automated Installation)

### 1. Prepare a fresh Debian Trixie x64 installation on the Pi

- Flash Raspberry Pi OS (Debian Trixie x64) to an SD card
- Boot the Pi and ensure it has network connectivity
- SSH into the Pi as user `admin`

### 2. Copy the project to the Pi

From your workstation:

```bash
# Copy the entire project directory to the Pi
scp -r cnc-pi0-usb-sync admin@<pi-hostname-or-ip>:~/
scp bootstrap-cncpi_l.sh admin@<pi-hostname-or-ip>:~/
```

### 3. Run the bootstrap script

SSH into the Pi and run:

```bash
cd ~
chmod +x bootstrap-cncpi_l.sh
./bootstrap-cncpi_l.sh
```

The bootstrap script will automatically:
- Install required packages (network-manager, cifs-utils, unison, rsync, dosfstools)
- Add Weld-KC01 to /etc/hosts
- Create SMB credentials file at `/etc/samba/credentials-cnc`
- Create systemd mount units for the network share
- Create the `/piusb.bin` disk image (8GB vfat)
- Install the cnc-sync script to `/usr/local/sbin/cnc-sync`
- Create all systemd service/timer units:
  - `cnc-sync.service` + `cnc-sync.timer` (share-change only, every 10 min)
  - `cnc-sync-full.service` + `cnc-sync-full.timer` (full sync every hour)
  - `usb-gadget.service` (USB mass storage gadget)
- Add helpful bash aliases (sync, status, off, fix)
- Enable and start all services

### 4. Configure per-Pi settings

After the bootstrap completes, edit the cnc-sync script for your specific machine:

```bash
sudo nano /usr/local/sbin/cnc-sync
```

Set the appropriate values:

```bash
CNC_HOSTNAME="cnc120"    # Change to your machine's hostname
SHARE_ROOT="/mnt/cncshare/Master Proven Prg/Mill/120-123 new 8-22"  # Change to your share path
```

For example:
- Mills 120-123: `/mnt/cncshare/Master Proven Prg/Mill/120-123 new 8-22`
- Lathe 030: `/mnt/cncshare/Master Proven Prg/Lathe/`

### 5. Verify the SMB credentials

If needed, update the credentials file:

```bash
sudo nano /etc/samba/credentials-cnc
```

Ensure it contains:
```
username=SCAN4@weldracing.local
password=Klimb-100
```

### 6. Test the sync

Reload the configuration and run a test sync:

```bash
sudo systemctl daemon-reload
sync  # This is an alias for: sudo systemctl start cnc-sync.service
```

Check the logs:
```bash
status  # Shows service status and last 20 log lines
```

---

## Manual Installation (Advanced)

If you prefer manual installation or need to troubleshoot, follow these steps:

### 1. Copy files from repo to the Pi

```bash
# Copy the cnc-sync script
scp cnc-pi0-usb-sync/scripts/cnc-sync admin@<pi-ip>:/home/admin/
ssh admin@<pi-ip> "sudo mv /home/admin/cnc-sync /usr/local/sbin/cnc-sync && sudo chmod 755 /usr/local/sbin/cnc-sync"

# Copy systemd units
scp cnc-pi0-usb-sync/systemd/*.service cnc-pi0-usb-sync/systemd/*.timer admin@<pi-ip>:/home/admin/
ssh admin@<pi-ip> "sudo mv /home/admin/*.service /home/admin/*.timer /etc/systemd/system/"
```

### 2. Configure the cnc-sync script

Edit `/usr/local/sbin/cnc-sync` on the Pi:

```bash
sudo nano /usr/local/sbin/cnc-sync
```

Set:
```bash
CNC_HOSTNAME="cnc120"
SHARE_ROOT="/mnt/cncshare/Master Proven Prg/Mill/120-123 new 8-22"
```

### 3. Enable and start services

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now usb-gadget.service
sudo systemctl enable --now cnc-sync.timer
sudo systemctl enable --now cnc-sync-full.timer
```

---

## Usage

### Convenient Aliases (Added by Bootstrap)

The bootstrap script adds these aliases to `~/.bashrc`:

- **`sync`** or **`hsync`**: Manually trigger a sync
- **`status`**: Show service status and recent logs
- **`off`**: Safely shut down the Pi (stops services, unmounts, powers off)
- **`fix`**: Repair utility (runs fsck, remounts, restarts services)

### Manual Commands

If you didn't use the bootstrap script, use these commands:

**Manual sync:**

**Manual sync:**
```bash
sudo systemctl start cnc-sync.service  # or use alias: sync
```

**Force full sync:**
```bash
sudo /usr/local/sbin/cnc-sync --full
```

**Check timer status:**
```bash
systemctl list-timers | grep cnc-sync
```

**View logs:**
```bash
sudo tail -n 100 /var/log/cnc-sync.log
# or use alias: status
```

---

## Timers and Sync Behavior

- **cnc-sync.timer**: Runs every 10 minutes
  - Checks if the network share has changed (hash comparison)
  - Only runs full sync if changes detected
  - Minimizes USB disconnections from CNC machine

- **cnc-sync-full.timer**: Runs every hour
  - Always performs full sync regardless of share changes
  - Captures any changes made directly on the CNC machine
  - Ensures two-way sync stays current

---

## Logs

Sync logs are written to:
- `/var/log/cnc-sync.log`

Use:
```bash
sudo tail -n 100 /var/log/cnc-sync.log
```
or the `status` alias to inspect recent activity.
