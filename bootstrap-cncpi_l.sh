#!/usr/bin/env bash
set -euo pipefail

LOG_TAG="[bootstrap-cncpi]"
SMB_SERVER="${SMB_SERVER:-fileserver.example.local}"
SMB_SHARE="${SMB_SHARE:-cnc-programs}"

echo "$LOG_TAG Starting CNCPi bootstrap..."

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
sudo mkdir -p /mnt/cncshare
sudo mkdir -p /mnt/piusb


# 3. Create credentials file
echo "$LOG_TAG Ensuring /etc/samba exists..."
sudo mkdir -p /etc/samba

CRED_FILE="/etc/samba/credentials-cnc"
NEED_CREDS_FIX=false

if [ ! -f "$CRED_FILE" ]; then
  echo "$LOG_TAG Creating $CRED_FILE with placeholder credentials..."
  sudo bash -c "cat > '$CRED_FILE' <<'EOF'
username=YOUR_SMB_USERNAME
password=YOUR_SMB_PASSWORD
EOF
"
  sudo chmod 600 "$CRED_FILE"
  NEED_CREDS_FIX=true
else
  echo "$LOG_TAG $CRED_FILE already exists, leaving it alone."
  if grep -q 'YOUR_SMB_PASSWORD' "$CRED_FILE"; then
    NEED_CREDS_FIX=true
  fi
fi

# 4. Create mnt-cncshare.mount
echo "$LOG_TAG Writing /etc/systemd/system/mnt-cncshare.mount..."
sudo tee /etc/systemd/system/mnt-cncshare.mount >/dev/null <<EOF
[Unit]
Description=SMB mount for CNC share
After=network-online.target
Wants=network-online.target

[Mount]
What=//${SMB_SERVER}/${SMB_SHARE}
Where=/mnt/cncshare
Type=cifs
Options=credentials=/etc/samba/credentials-cnc,iocharset=utf8,vers=3.0,sec=ntlmssp,noperm,uid=1000,gid=1000,file_mode=0775,dir_mode=0775

[Install]
WantedBy=multi-user.target
EOF

# 5. Create mnt-cncshare.automount
echo "$LOG_TAG Writing /etc/systemd/system/mnt-cncshare.automount..."
sudo bash -c 'cat > /etc/systemd/system/mnt-cncshare.automount <<EOF
[Unit]
Description=Automount CNC SMB share at /mnt/cncshare

[Automount]
Where=/mnt/cncshare

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

# 7. Install cnc-sync script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/cnc-pi0-usb-sync/scripts/cnc-sync" ]; then
  echo "$LOG_TAG Installing cnc-sync script to /usr/local/sbin/cnc-sync..."
  sudo cp "$SCRIPT_DIR/cnc-pi0-usb-sync/scripts/cnc-sync" /usr/local/sbin/cnc-sync
  sudo chmod 755 /usr/local/sbin/cnc-sync
else
  echo "$LOG_TAG WARNING: cnc-sync script not found at $SCRIPT_DIR/cnc-pi0-usb-sync/scripts/cnc-sync"
  echo "$LOG_TAG You will need to install it manually."
fi

# 8. Create cnc-sync.service
echo "$LOG_TAG Writing /etc/systemd/system/cnc-sync.service..."
sudo bash -c 'cat > /etc/systemd/system/cnc-sync.service <<EOF
[Unit]
Description=Sync CNC USB image with CNC share (share-change only)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/cnc-sync
EOF'

# 9. Create cnc-sync.timer
echo "$LOG_TAG Writing /etc/systemd/system/cnc-sync.timer..."
sudo bash -c 'cat > /etc/systemd/system/cnc-sync.timer <<EOF
[Unit]
Description=Run cnc-sync every 10 minutes (share-change only)

[Timer]
OnBootSec=60
OnUnitActiveSec=600
Unit=cnc-sync.service

[Install]
WantedBy=timers.target
EOF'

# 10. Create cnc-sync-full.service
echo "$LOG_TAG Writing /etc/systemd/system/cnc-sync-full.service..."
sudo bash -c 'cat > /etc/systemd/system/cnc-sync-full.service <<EOF
[Unit]
Description=Full CNC sync (force detach/mount/unison)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/cnc-sync --full
EOF'

# 11. Create cnc-sync-full.timer
echo "$LOG_TAG Writing /etc/systemd/system/cnc-sync-full.timer..."
sudo bash -c 'cat > /etc/systemd/system/cnc-sync-full.timer <<EOF
[Unit]
Description=Run full cnc-sync every hour

[Timer]
OnBootSec=300
OnUnitActiveSec=3600
Unit=cnc-sync-full.service

[Install]
WantedBy=timers.target
EOF'

# 12. Create usb-gadget.service
echo "$LOG_TAG Writing /etc/systemd/system/usb-gadget.service..."
sudo bash -c 'cat > /etc/systemd/system/usb-gadget.service <<EOF
[Unit]
Description=USB Mass Storage Gadget for CNC
After=local-fs.target
Requires=local-fs.target

[Service]
Type=oneshot
ExecStart=/sbin/modprobe g_mass_storage file=/piusb.bin stall=0 removable=1 ro=0

[Install]
WantedBy=multi-user.target
EOF'

# 13. Create state directory for cnc-sync
echo "$LOG_TAG Creating /var/lib/cnc-sync state directory..."
sudo mkdir -p /var/lib/cnc-sync

# 14. Append aliases/functions to ~/.bashrc if not present
BASHRC="$HOME/.bashrc"
MARKER="# BEGIN CNCPI HELPERS"

if ! grep -q "$MARKER" "$BASHRC"; then
  echo "$LOG_TAG Adding helpers to $BASHRC..."
  cat >> "$BASHRC" <<'EOF'

# BEGIN CNCPI HELPERS
# Run a sync (assumes passwordless sudo for systemctl start cnc-sync.service)
# Note: 'sync' is a system command, so we use cnc-sync or hsync instead
alias cnc-sync='sudo systemctl start cnc-sync.service'
alias hsync='cnc-sync'

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
# END CNCPI HELPERS
EOF
else
  echo "$LOG_TAG Helpers already present in $BASHRC; leaving them."
fi

# 15. Enable units and (optionally) run initial sync
echo "$LOG_TAG Reloading systemd units..."
sudo systemctl daemon-reload

echo "$LOG_TAG Enabling automount, USB gadget, and sync timers..."
sudo systemctl enable mnt-cncshare.automount
sudo systemctl enable usb-gadget.service
sudo systemctl enable cnc-sync.timer
sudo systemctl enable cnc-sync-full.timer

echo "$LOG_TAG Starting automount, USB gadget, and timers..."
sudo systemctl start mnt-cncshare.automount
sudo systemctl start usb-gadget.service
sudo systemctl start cnc-sync.timer
sudo systemctl start cnc-sync-full.timer

if [ "$NEED_CREDS_FIX" = true ]; then
  echo "$LOG_TAG Skipping initial sync because $CRED_FILE still has placeholder credentials."
  echo "$LOG_TAG Edit $CRED_FILE with your SMB credentials, then run: hsync"
else
  echo "$LOG_TAG Forcing one initial sync..."
  sudo systemctl start cnc-sync.service
fi

echo "$LOG_TAG Bootstrap complete."
echo "$LOG_TAG"
echo "$LOG_TAG NEXT STEPS:"
echo "$LOG_TAG 1. Edit /usr/local/sbin/cnc-sync and set:"
echo "$LOG_TAG    - CNC_HOSTNAME (the CNC name used for this installation)"
echo "$LOG_TAG    - SHARE_ROOT (path to your CNC programs on the network share)"
echo "$LOG_TAG 2. If needed, edit $CRED_FILE and verify the password"
echo "$LOG_TAG 3. Test with: hsync (or 'cnc-sync')"
echo "$LOG_TAG 4. Check logs with: status"
echo "$LOG_TAG"
