# Deployment – Haas Pi Zero 2W USB Sync

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
scp -r haas-pi0-usb-sync admin@<pi-hostname-or-ip>:~/
scp bootstrap-haaspi_l.sh admin@<pi-hostname-or-ip>:~/
```

### 3. Run the bootstrap script

SSH into the Pi and run:

```bash
cd ~
chmod +x bootstrap-haaspi_l.sh
./bootstrap-haaspi_l.sh
```

The bootstrap script will automatically:
- Install required packages (network-manager, cifs-utils, unison, rsync, dosfstools)
- Add Weld-KC01 to /etc/hosts
- Create SMB credentials file at `/etc/samba/credentials-haas`
- Create systemd mount units for the network share
- Create the `/piusb.bin` disk image (8GB vfat)
- Install the haas-sync script to `/usr/local/sbin/haas-sync`
- Create all systemd service/timer units:
  - `haas-sync.service` + `haas-sync.timer` (share-change only, every 10 min)
  - `haas-sync-full.service` + `haas-sync-full.timer` (full sync every hour)
  - `usb-gadget.service` (USB mass storage gadget)
- Add helpful bash aliases (sync, status, off, fix)
- Enable and start all services

### 4. Configure per-Pi settings

After the bootstrap completes, edit the haas-sync script for your specific machine:

```bash
sudo nano /usr/local/sbin/haas-sync
```

Set the appropriate values:

```bash
HAAS_HOSTNAME="haas120"    # Change to your machine's hostname
SHARE_ROOT="/mnt/haasshare/Master Proven Prg/Mill/120-123 new 8-22"  # Change to your share path
```

For example:
- Mills 120-123: `/mnt/haasshare/Master Proven Prg/Mill/120-123 new 8-22`
- Lathe 030: `/mnt/haasshare/Master Proven Prg/Lathe/`

### 5. Verify the SMB credentials

If needed, update the credentials file:

```bash
sudo nano /etc/samba/credentials-haas
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
sync  # This is an alias for: sudo systemctl start haas-sync.service
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
# Copy the haas-sync script
scp haas-pi0-usb-sync/scripts/haas-sync admin@<pi-ip>:/home/admin/
ssh admin@<pi-ip> "sudo mv /home/admin/haas-sync /usr/local/sbin/haas-sync && sudo chmod 755 /usr/local/sbin/haas-sync"

# Copy systemd units
scp haas-pi0-usb-sync/systemd/*.service haas-pi0-usb-sync/systemd/*.timer admin@<pi-ip>:/home/admin/
ssh admin@<pi-ip> "sudo mv /home/admin/*.service /home/admin/*.timer /etc/systemd/system/"
```

### 2. Configure the haas-sync script

Edit `/usr/local/sbin/haas-sync` on the Pi:

```bash
sudo nano /usr/local/sbin/haas-sync
```

Set:
```bash
HAAS_HOSTNAME="haas120"
SHARE_ROOT="/mnt/haasshare/Master Proven Prg/Mill/120-123 new 8-22"
```

### 3. Enable and start services

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now usb-gadget.service
sudo systemctl enable --now haas-sync.timer
sudo systemctl enable --now haas-sync-full.timer
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
sudo systemctl start haas-sync.service  # or use alias: sync
```

**Force full sync:**
```bash
sudo /usr/local/sbin/haas-sync --full
```

**Check timer status:**
```bash
systemctl list-timers | grep haas-sync
```

**View logs:**
```bash
sudo tail -n 100 /var/log/haas-sync.log
# or use alias: status
```

---

## Timers and Sync Behavior

- **haas-sync.timer**: Runs every 10 minutes
  - Checks if the network share has changed (hash comparison)
  - Only runs full sync if changes detected
  - Minimizes USB disconnections from CNC machine

- **haas-sync-full.timer**: Runs every hour
  - Always performs full sync regardless of share changes
  - Captures any changes made directly on the CNC machine
  - Ensures two-way sync stays current

---

## Logs

Sync logs are written to:
- `/var/log/haas-sync.log`

Use:
```bash
sudo tail -n 100 /var/log/haas-sync.log
```
or the `status` alias to inspect recent activity.
