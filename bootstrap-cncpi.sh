#!/usr/bin/env bash
set -euo pipefail

echo "[bootstrap-cncpi] Starting…"

ADMIN_USER="admin"
ADMIN_UID=1000
ADMIN_GID=1000

CNC_HOSTNAME="${CNC_HOSTNAME:-$(hostname)}"
CNC_SHARE_SERVER="${CNC_SHARE_SERVER:-fileserver.example.local}"
CNC_SHARE_NAME="${CNC_SHARE_NAME:-cnc-programs}"
CNC_SHARE="//${CNC_SHARE_SERVER}/${CNC_SHARE_NAME}"
CRED_FILE="/etc/samba/credentials-cnc"
USB_IMG="/piusb.bin"
USB_MNT="/mnt/piusb"
CNC_MNT="/mnt/cncshare"

# ------------------ 0. Packages ------------------
echo "[bootstrap-cncpi] Installing required packages (network-manager, cifs-utils, unison, rsync, dosfstools)…"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  network-manager cifs-utils unison rsync dosfstools

# ------------------ 1. Boot configuration ------------------
echo "[bootstrap-cncpi] Setting up /boot/firmware/config.txt for USB gadget mode…"
sudo bash -c 'cat > /boot/firmware/config.txt' << 'BOOTCFG'
# For more options and information see
# http://rptl.io/configtxt
# Some settings may impact device functionality. See link above for details

# Uncomment some or all of these to enable the optional hardware interfaces
#dtparam=i2c_arm=on
#dtparam=i2s=on
#dtparam=spi=on

# Enable audio (loads snd_bcm2835)
#dtparam=audio=on

# Additional overlays and parameters are documented
# /boot/firmware/overlays/README

# Automatically load overlays for detected cameras
#camera_auto_detect=1

# Automatically load overlays for detected DSI displays
display_auto_detect=1

# Automatically load initramfs files, if found
auto_initramfs=1

# Enable DRM VC4 V3D driver
#dtoverlay=vc4-kms-v3d
#max_framebuffers=2

# Don't have the firmware create an initial video= setting in cmdline.txt.
# Use the kernel's default instead.
disable_fw_kms_setup=1

# Run in 64-bit mode
arm_64bit=1

# Disable compensation for displays with overscan
disable_overscan=1

# Run as fast as firmware / board allows
#arm_boost=1

[all]
# Enable USB gadget mode on Zero 2W
dtoverlay=dwc2,dr_mode=peripheral

hdmi_force_hotplug=1
hdmi_group=2
hdmi_mode=82
BOOTCFG

echo "[bootstrap-cncpi] Setting up /boot/firmware/cmdline.txt for USB gadget kernel parameters…"
sudo bash -c 'cat > /boot/firmware/cmdline.txt' << 'CMDLINE'
console=serial0,115200 console=tty1 root=PARTUUID=8597b831-02 rootfstype=ext4 fsck.repair=yes rootwait quiet modules-load=dwc2,g_mass_storage g_mass_storage.file=/piusb.img g_mass_storage.ro=0 g_mass_storage.stall=0 g_mass_storage.removable=1
CMDLINE

# ------------------ 3. Samba credentials ------------------
echo "[bootstrap-cncpi] Ensuring /etc/samba and credentials file…"
sudo mkdir -p /etc/samba

if [ ! -f "${CRED_FILE}" ]; then
  echo "[bootstrap-cncpi] Creating ${CRED_FILE} with placeholder credentials…"
  sudo bash -c "cat > '${CRED_FILE}'" << 'CREDS'
username=YOUR_SMB_USERNAME
password=YOUR_SMB_PASSWORD
CREDS
  sudo chmod 600 "${CRED_FILE}"
else
  echo "[bootstrap-cncpi] ${CRED_FILE} already exists; leaving it unchanged."
fi

# ------------------ 4. CIFS automount ------------------
echo "[bootstrap-cncpi] Setting up CIFS automount at ${CNC_MNT}…"
sudo mkdir -p "${CNC_MNT}"

sudo bash -c "cat > /etc/systemd/system/mnt-cncshare.mount" << MNT
[Unit]
Description=SMB mount for CNC share
After=network-online.target
Wants=network-online.target

[Mount]
What=${CNC_SHARE}
Where=${CNC_MNT}
Type=cifs
Options=credentials=${CRED_FILE},uid=${ADMIN_UID},gid=${ADMIN_GID},file_mode=0664,dir_mode=0775,vers=3.0,noserverino,iocharset=utf8

[Install]
WantedBy=multi-user.target
MNT

sudo bash -c "cat > /etc/systemd/system/mnt-cncshare.automount" << AMT
[Unit]
Description=Automount CNC SMB share at ${CNC_MNT}

[Automount]
Where=${CNC_MNT}

[Install]
WantedBy=multi-user.target
AMT

# ------------------ 5. USB image ------------------
echo "[bootstrap-cncpi] Ensuring ${USB_IMG} exists…"
if [ ! -f "${USB_IMG}" ]; then
  echo "[bootstrap-cncpi] Creating 8GB USB image at ${USB_IMG}…"
  sudo dd if=/dev/zero of="${USB_IMG}" bs=1G count=8 status=progress
  sudo mkfs.vfat -F 32 "${USB_IMG}"
  sudo chown "${ADMIN_USER}:${ADMIN_USER}" "${USB_IMG}"
else
  echo "[bootstrap-cncpi] ${USB_IMG} already exists; leaving it."
fi

sudo mkdir -p "${USB_MNT}"

# ------------------ 6. cnc-sync.sh ------------------
# echo "[bootstrap-cncpi] Installing /home/${ADMIN_USER}/cnc-sync.sh…"
sudo bash -c "cat > /home/${ADMIN_USER}/cnc-sync.sh" << 'SYNC'
!/usr/bin/env bash
set -euo pipefail

LOG=/var/log/cnc-sync.log

USB_IMG="/piusb.bin"
USB_MNT="/mnt/piusb"

ADMIN_UID=1000
ADMIN_GID=1000

# Treat USB as "empty/wiped" if it has very few files
MIN_USB_FILES=10
# Treat share as "healthy" if it has at least this many files
MIN_SHARE_FILES=100

timestamp() {
  date +"%Y-%m-%dT%H:%M:%S%z"
}

log() {
  echo "[$(timestamp)] cnc-sync: $*" | tee -a "$LOG"
}

SHARE_ROOT="/mnt/cncshare/programs"

log "Using SHARE_ROOT='$SHARE_ROOT' for hostname '$HOSTNAME'."
log "start"

# Sanity checks
if [ ! -f "$USB_IMG" ]; then
  log "ERROR: $USB_IMG does not exist; aborting."
  exit 1
fi

# Ensure SMB share is mounted via automount
if ! mountpoint -q /mnt/cncshare; then
  log "Forcing SMB automount by listing /mnt/cncshare..."
  if ! ls /mnt/cncshare >/dev/null 2>&1; then
    log "ERROR: Unable to access /mnt/cncshare; aborting sync."
    exit 1
  fi
fi

# Detach USB gadget if present
if lsmod | grep -q g_mass_storage; then
  log "Detaching g_mass_storage..."
  if ! sudo modprobe -r g_mass_storage 2>/dev/null; then
    log "WARNING: Failed to remove g_mass_storage module (may not be loaded)."
  fi
fi

# Ensure USB mountpoint exists
sudo mkdir -p "$USB_MNT"

# If already mounted, unmount cleanly first
if mountpoint -q "$USB_MNT"; then
  log "$USB_MNT is already mounted; unmounting before sync..."
  if ! sudo umount "$USB_MNT"; then
    log "ERROR: Failed to unmount $USB_MNT; aborting."
    exit 1
  fi
fi

# Mount USB image RW
log "Mounting $USB_IMG to $USB_MNT (rw,uid=$ADMIN_UID,gid=$ADMIN_GID,umask=002)..."
sudo mount -o loop,rw,uid="$ADMIN_UID",gid="$ADMIN_GID",umask=002 "$USB_IMG" "$USB_MNT"

# Measure sizes and counts
usb_used=$(df -B1 "$USB_MNT"       | awk 'NR==2 {print $3}')
share_used=$(df -B1 "$SHARE_ROOT"  | awk 'NR==2 {print $3}' || echo 0)
usb_files=$(find "$USB_MNT"      -mindepth 1 -type f 2>/dev/null | wc -l || echo 0)
share_files=$(find "$SHARE_ROOT" -mindepth 1 -type f 2>/dev/null | wc -l || echo 0)

log "USB used=${usb_used}B, files=${usb_files}; SHARE used=${share_used}B, files=${share_files}"

# Protection logic:
# 1) USB looks empty but share is populated -> rebuild USB from share (safe)
# 2) Share looks empty but USB is populated -> refuse to sync to avoid deleting share
# 3) Otherwise -> normal two-way Unison
if [ "$usb_files" -lt "$MIN_USB_FILES" ] && [ "$share_files" -gt "$MIN_SHARE_FILES" ]; then
  log "USB side has very few files while share is populated; treating USB as empty and copying share -> USB."
  sudo rsync -a --delete "$SHARE_ROOT"/ "$USB_MNT"/
elif [ "$share_files" -lt "$MIN_SHARE_FILES" ] && [ "$usb_files" -gt "$MIN_USB_FILES" ]; then
  log "Share side has very few files while USB is populated; refusing to sync to avoid deleting share."
  log "Leaving both sides unchanged; please investigate share path and rerun manually."
else
  log "Starting Unison two-way sync..."
  sudo -u admin unison "$USB_MNT" "$SHARE_ROOT" -auto -batch -perms 0
  log "Unison complete."
fi

log "Unmounting $USB_MNT..."
sudo umount "$USB_MNT"

log "Reattaching g_mass_storage in RW mode..."
if ! sudo modprobe g_mass_storage file="$USB_IMG" stall=0 removable=1 2>/dev/null; then
  log "ERROR: Failed to load g_mass_storage with $USB_IMG"
  exit 1
fi

log "done"
SYNC

sudo chmod +x /home/${ADMIN_USER}/cnc-sync.sh
sudo chown ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/cnc-sync.sh

# ------------------ 6. systemd units ------------------
echo "[bootstrap-cncpi] Writing cnc-sync.service and cnc-sync.timer…"

sudo bash -c "cat > /etc/systemd/system/cnc-sync.service" << 'SRV'
[Unit]
Description=Sync SMB share to local USB image and attach RW (g_mass_storage)
After=network-online.target mnt-cncshare.automount
Wants=network-online.target

[Service]
Type=oneshot
User=root
Group=root
ExecStart=/usr/bin/flock -n /run/lock/cnc-sync.lock /home/admin/cnc-sync.sh
Nice=10

[Install]
WantedBy=multi-user.target
SRV

sudo bash -c "cat > /etc/systemd/system/cnc-sync.timer" << 'TMR'
[Unit]
Description=Periodic sync of CNC SMB share to USB image

[Timer]
OnBootSec=30s
OnUnitActiveSec=600s
Unit=cnc-sync.service

[Install]
WantedBy=timers.target
TMR

# ------------------ 7. Bash helpers ------------------
echo "[bootstrap-cncpi] Ensuring CNCPi helpers (hsync, status, fix, off) are present in ~/.bashrc…"

BASHRC="/home/${ADMIN_USER}/.bashrc"

# Remove any existing CNCPi helper block (old or new) to avoid duplicates
sudo sed -i '/# --- CNCPi helpers BEGIN ---/,/# --- CNCPi helpers END ---/d' "${BASHRC}" 2>/dev/null || true
sudo sed -i '/# BEGIN CNCPI HELPERS/,/# END CNCPI HELPERS/d' "${BASHRC}" 2>/dev/null || true

# Append a single canonical helper block
sudo bash -c "cat >> '${BASHRC}'" << 'BRC'

# --- CNCPi helpers BEGIN ---
alias cnc-sync='sudo systemctl start cnc-sync.service'
alias hsync='cnc-sync'

status() {
  echo "=== cnc-sync.service ==="
  systemctl status cnc-sync.service --no-pager
  echo
  echo "=== cnc-sync.timer ==="
  systemctl status cnc-sync.timer --no-pager
  echo
  echo "=== last 20 lines of /var/log/cnc-sync.log ==="
  sudo tail -n 20 /var/log/cnc-sync.log || true
}

fix() {
  echo "[fix] Checking CIFS automount…"
  systemctl status mnt-cncshare.automount --no-pager || true
  echo
  echo "[fix] Checking mount unit…"
  systemctl status mnt-cncshare.mount --no-pager || true
  echo
  echo "[fix] Forcing one sync run…"
  sudo systemctl start cnc-sync.service
}

off() {
  echo "Shutting down Pi in 5 seconds…"
  sleep 5
  sudo shutdown -h now
}
# --- CNCPi helpers END ---

BRC

# ------------------ 8. Enable units & initial sync ------------------
echo "[bootstrap-cncpi] Reloading systemd and enabling units…"
sudo systemctl daemon-reload
sudo systemctl enable mnt-cncshare.automount cnc-sync.timer >/dev/null

echo "[bootstrap-cncpi] Starting automount and timer…"
sudo systemctl start mnt-cncshare.automount
sudo systemctl start cnc-sync.timer

echo "[bootstrap-cncpi] Forcing one initial sync…"
sudo systemctl start cnc-sync.service || true

echo "[bootstrap-cncpi] Done. You may want to 'exec bash' or log out/in to pick up new helpers."
source ~/.bashrc
echo "[bootstrap-cncpi] Finished."
