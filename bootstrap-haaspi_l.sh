#!/usr/bin/env bash
set -euo pipefail

LOG_TAG="[bootstrap-haaspi]"

echo "$LOG_TAG Starting HaasPi bootstrap..."

if [ "$(id -un)" != "admin" ]; then
  echo "$LOG_TAG This script is intended to be run as user 'admin'."
  echo "$LOG_TAG You are '$(id -un)'. Continue anyway? (Ctrl+C to abort)"
  read -r _
fi

# 1. Install required packages
echo "$LOG_TAG Updating APT and installing packages..."
sudo apt update
sudo apt install -y network-manager cifs-utils unison rsync dosfstools

# 2. Create mountpoints
echo "$LOG_TAG Ensuring mount points exist..."
sudo mkdir -p /mnt/haasshare
sudo mkdir -p /mnt/piusb


# Ensure Weld-KC01 is resolvable
if ! grep -q 'Weld-KC01' /etc/hosts; then
  echo "$LOG_TAG Adding Weld-KC01 to /etc/hosts..."
  echo '192.168.126.128    Weld-KC01' | sudo tee -a /etc/hosts >/dev/null
else
  echo "$LOG_TAG /etc/hosts already has Weld-KC01 entry; leaving it."
fi

# 3. Create credentials file
echo "$LOG_TAG Ensuring /etc/samba exists..."
sudo mkdir -p /etc/samba

CRED_FILE="/etc/samba/credentials-haas"
NEED_CREDS_FIX=false

if [ ! -f "$CRED_FILE" ]; then
  echo "$LOG_TAG Creating $CRED_FILE with password..."
  sudo bash -c "cat > '$CRED_FILE' <<'EOF'
username=SCAN4@weldracing.local
password=Klimb-100
EOF
"
  sudo chmod 600 "$CRED_FILE"
  NEED_CREDS_FIX=true
else
  echo "$LOG_TAG $CRED_FILE already exists, leaving it alone."
  if grep -q 'password=CHANGE_ME' "$CRED_FILE"; then
    NEED_CREDS_FIX=true
  fi
fi

# 4. Create mnt-haasshare.mount
echo "$LOG_TAG Writing /etc/systemd/system/mnt-haasshare.mount..."
sudo bash -c 'cat > /etc/systemd/system/mnt-haasshare.mount <<EOF
[Unit]
Description=SMB mount for Haas share (Weld-KC01\\cnc programs)
After=network-online.target
Wants=network-online.target

[Mount]
What=//Weld-KC01/cnc programs
Where=/mnt/haasshare
Type=cifs
Options=credentials=/etc/samba/credentials-haas,iocharset=utf8,vers=3.0,sec=ntlmssp,noperm,uid=1000,gid=1000,file_mode=0775,dir_mode=0775

[Install]
WantedBy=multi-user.target
EOF'

# 5. Create mnt-haasshare.automount
echo "$LOG_TAG Writing /etc/systemd/system/mnt-haasshare.automount..."
sudo bash -c 'cat > /etc/systemd/system/mnt-haasshare.automount <<EOF
[Unit]
Description=Automount Haas SMB share at /mnt/haasshare

[Automount]
Where=/mnt/haasshare

[Install]
WantedBy=multi-user.target
EOF'

# 6. Ensure /piusb.bin exists and is formatted
if [ ! -f /piusb.bin ]; then
  echo "$LOG_TAG Creating /piusb.bin 8GB sparse file and formatting as vfat..."
  sudo dd if=/dev/zero of=/piusb.bin bs=1M count=0 seek=8192
  sudo mkfs.vfat /piusb.bin
  if [ ! -f /piusb.bin ]; then
    echo "$LOG_TAG ERROR: Failed to create /piusb.bin!"
    exit 1
  fi
else
  echo "$LOG_TAG /piusb.bin already exists; leaving it in place."
fi

# 7. Install haas-sync script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/haas-pi0-usb-sync/scripts/haas-sync" ]; then
  echo "$LOG_TAG Installing haas-sync script to /usr/local/sbin/haas-sync..."
  sudo cp "$SCRIPT_DIR/haas-pi0-usb-sync/scripts/haas-sync" /usr/local/sbin/haas-sync
  sudo chmod 755 /usr/local/sbin/haas-sync
else
  echo "$LOG_TAG WARNING: haas-sync script not found at $SCRIPT_DIR/haas-pi0-usb-sync/scripts/haas-sync"
  echo "$LOG_TAG You will need to install it manually."
fi

# 8. Create haas-sync.service
echo "$LOG_TAG Writing /etc/systemd/system/haas-sync.service..."
sudo bash -c 'cat > /etc/systemd/system/haas-sync.service <<EOF
[Unit]
Description=Sync HAAS USB image with CNC share (share-change only)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/haas-sync
EOF'

# 9. Create haas-sync.timer
echo "$LOG_TAG Writing /etc/systemd/system/haas-sync.timer..."
sudo bash -c 'cat > /etc/systemd/system/haas-sync.timer <<EOF
[Unit]
Description=Run haas-sync every 10 minutes (share-change only)

[Timer]
OnBootSec=60
OnUnitActiveSec=600
Unit=haas-sync.service

[Install]
WantedBy=timers.target
EOF'

# 10. Create haas-sync-full.service
echo "$LOG_TAG Writing /etc/systemd/system/haas-sync-full.service..."
sudo bash -c 'cat > /etc/systemd/system/haas-sync-full.service <<EOF
[Unit]
Description=Full HAAS sync (force detach/mount/unison)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/haas-sync --full
EOF'

# 11. Create haas-sync-full.timer
echo "$LOG_TAG Writing /etc/systemd/system/haas-sync-full.timer..."
sudo bash -c 'cat > /etc/systemd/system/haas-sync-full.timer <<EOF
[Unit]
Description=Run full haas-sync every hour

[Timer]
OnBootSec=300
OnUnitActiveSec=3600
Unit=haas-sync-full.service

[Install]
WantedBy=timers.target
EOF'

# 12. Create usb-gadget.service
echo "$LOG_TAG Writing /etc/systemd/system/usb-gadget.service..."
sudo bash -c 'cat > /etc/systemd/system/usb-gadget.service <<EOF
[Unit]
Description=USB Mass Storage Gadget for HAAS
After=local-fs.target
Requires=local-fs.target

[Service]
Type=oneshot
ExecStart=/sbin/modprobe g_mass_storage file=/piusb.bin stall=0 removable=1 ro=0

[Install]
WantedBy=multi-user.target
EOF'

# 13. Create state directory for haas-sync
echo "$LOG_TAG Creating /var/lib/haas-sync state directory..."
sudo mkdir -p /var/lib/haas-sync

# 14. Append aliases/functions to ~/.bashrc if not present
BASHRC="$HOME/.bashrc"
MARKER="# BEGIN HAASPI HELPERS"

if ! grep -q "$MARKER" "$BASHRC"; then
  echo "$LOG_TAG Adding helpers to $BASHRC..."
  cat >> "$BASHRC" <<'EOF'

# BEGIN HAASPI HELPERS
# Run a sync (assumes passwordless sudo for systemctl start haas-sync.service)
# Note: 'sync' is a system command, so we use haas-sync or hsync instead
alias haas-sync='sudo systemctl start haas-sync.service'
alias hsync='haas-sync'

status() {
  echo "=== haas-sync.service ==="
  sudo systemctl status haas-sync.service --no-pager
  echo
  echo "=== haas-sync.timer ==="
  sudo systemctl status haas-sync.timer --no-pager
  echo
  echo "=== last 20 lines of /var/log/haas-sync.log ==="
  sudo tail -n 20 /var/log/haas-sync.log
}

off() {
  echo "[off] Stopping haas-sync timer and service..."
  sudo systemctl stop haas-sync.timer 2>/dev/null || true
  sudo systemctl stop haas-sync.service 2>/dev/null || true

  echo "[off] Detaching USB gadget and unmounting filesystems..."
  sudo modprobe -r g_mass_storage 2>/dev/null || true
  sudo umount /mnt/piusb 2>/dev/null || true
  sudo umount /mnt/haasshare 2>/dev/null || true

  echo "[off] Shutting down Pi now..."
  sudo shutdown -h now
}

fix() {
  echo "[fix] Checking Haas Pi USB setup..."

  if [ ! -f /etc/samba/credentials-haas ]; then
    echo "[fix] ERROR: /etc/samba/credentials-haas not found."
    return 1
  fi

  if [ ! -f /piusb.bin ]; then
    echo "[fix] ERROR: /piusb.bin not found."
    return 1
  fi

  echo "[fix] Reloading systemd units and ensuring automount is enabled..."
  sudo systemctl daemon-reload
  sudo systemctl enable mnt-haasshare.automount >/dev/null 2>&1 || true
  sudo systemctl start mnt-haasshare.automount >/dev/null 2>&1 || true

  echo "[fix] Forcing SMB mount (ls /mnt/haasshare)..."
  if ! ls /mnt/haasshare >/dev/null 2>&1; then
    echo "[fix] ERROR: Unable to list /mnt/haasshare."
    return 1
  fi

  echo "[fix] Stopping haas-sync timer and service..."
  sudo systemctl stop haas-sync.timer 2>/dev/null || true
  sudo systemctl stop haas-sync.service 2>/dev/null || true

  echo "[fix] Detaching g_mass_storage and unmounting /mnt/piusb..."
  sudo modprobe -r g_mass_storage 2>/dev/null || true
  sudo umount /mnt/piusb 2>/dev/null || true

  echo "[fix] Running fsck.vfat on /piusb.bin (auto-fix)..."
  sudo fsck.vfat -a /piusb.bin

  echo "[fix] Reattaching g_mass_storage (RW)..."
  sudo modprobe g_mass_storage file=/piusb.bin stall=0 removable=1

  echo "[fix] Restarting haas-sync.timer..."
  sudo systemctl start haas-sync.timer 2>/dev/null || true

  echo "[fix] Forcing one haas-sync.service run..."
  sudo systemctl start haas-sync.service

  echo "[fix] Done. Use 'status' to verify recent sync logs."
}
# END HAASPI HELPERS
EOF
else
  echo "$LOG_TAG Helpers already present in $BASHRC; leaving them."
fi

# 15. Enable units and (optionally) run initial sync
echo "$LOG_TAG Reloading systemd units..."
sudo systemctl daemon-reload

echo "$LOG_TAG Enabling automount, USB gadget, and sync timers..."
sudo systemctl enable mnt-haasshare.automount
sudo systemctl enable usb-gadget.service
sudo systemctl enable haas-sync.timer
sudo systemctl enable haas-sync-full.timer

echo "$LOG_TAG Starting automount, USB gadget, and timers..."
sudo systemctl start mnt-haasshare.automount
sudo systemctl start usb-gadget.service
sudo systemctl start haas-sync.timer
sudo systemctl start haas-sync-full.timer

if [ "$NEED_CREDS_FIX" = true ]; then
  echo "$LOG_TAG Skipping initial sync because $CRED_FILE still has placeholder password."
  echo "$LOG_TAG Edit $CRED_FILE and set the real SCAN4 password, then run: hsync"
else
  echo "$LOG_TAG Forcing one initial sync..."
  sudo systemctl start haas-sync.service
fi

echo "$LOG_TAG Bootstrap complete."
echo "$LOG_TAG"
echo "$LOG_TAG NEXT STEPS:"
echo "$LOG_TAG 1. Edit /usr/local/sbin/haas-sync and set:"
echo "$LOG_TAG    - HAAS_HOSTNAME (e.g., 'haas030', 'haas120', 'haas122')"
echo "$LOG_TAG    - SHARE_ROOT (path to your CNC programs on the network share)"
echo "$LOG_TAG 2. If needed, edit $CRED_FILE and verify the password"
echo "$LOG_TAG 3. Test with: hsync (or 'haas-sync')"
echo "$LOG_TAG 4. Check logs with: status"
echo "$LOG_TAG"
