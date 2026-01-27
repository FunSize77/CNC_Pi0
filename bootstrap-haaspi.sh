-- Active: 1759788571275@@127.0.0.1@3306
#!/usr/bin/env bash
set -euo pipefail

echo "[bootstrap-haaspi] Starting…"

ADMIN_USER="admin"
ADMIN_UID=1000
ADMIN_GID=1000

HAAS_HOSTNAME="Weld-KC01"
HAAS_IP="192.168.126.128"
HAAS_SHARE="//${HAAS_HOSTNAME}/CNC Programs"
CRED_FILE="/etc/samba/credentials-haas"
USB_IMG="/piusb.bin"
USB_MNT="/mnt/piusb"
HAAS_MNT="/mnt/haasshare"

# ------------------ 0. Packages ------------------
echo "[bootstrap-haaspi] Installing required packages (network-manager, cifs-utils, unison, rsync, dosfstools)…"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  network-manager cifs-utils unison rsync dosfstools

# ------------------ 1. DNS / hosts ------------------
echo "[bootstrap-haaspi] Ensuring /etc/hosts has ${HAAS_HOSTNAME} -> ${HAAS_IP}…"
if ! grep -q "${HAAS_HOSTNAME}" /etc/hosts; then
  echo "${HAAS_IP}   ${HAAS_HOSTNAME}" | sudo tee -a /etc/hosts >/dev/null
else
  echo "[bootstrap-haaspi] ${HAAS_HOSTNAME} already present in /etc/hosts, leaving it."
fi

# ------------------ 2. Samba credentials ------------------
echo "[bootstrap-haaspi] Ensuring /etc/samba and credentials file…"
sudo mkdir -p /etc/samba

if [ ! -f "${CRED_FILE}" ]; then
  echo "[bootstrap-haaspi] Creating ${CRED_FILE} with default credentials (edit later if needed)…"
  sudo bash -c "cat > '${CRED_FILE}'" << 'CREDS'
username=SCAN4@weldracing.local
password=Klimb-100
CREDS
  sudo chmod 600 "${CRED_FILE}"
else
  echo "[bootstrap-haaspi] ${CRED_FILE} already exists; leaving it unchanged."
fi

# ------------------ 3. CIFS automount ------------------
echo "[bootstrap-haaspi] Setting up CIFS automount at ${HAAS_MNT}…"
sudo mkdir -p "${HAAS_MNT}"

sudo bash -c "cat > /etc/systemd/system/mnt-haasshare.mount" << MNT
[Unit]
Description=SMB mount for Haas share (${HAAS_HOSTNAME}\\CNC Programs)
After=network-online.target
Wants=network-online.target

[Mount]
What=${HAAS_SHARE}
Where=${HAAS_MNT}
Type=cifs
Options=credentials=${CRED_FILE},uid=${ADMIN_UID},gid=${ADMIN_GID},file_mode=0664,dir_mode=0775,vers=3.0,noserverino,iocharset=utf8

[Install]
WantedBy=multi-user.target
MNT

sudo bash -c "cat > /etc/systemd/system/mnt-haasshare.automount" << AMT
[Unit]
Description=Automount Haas SMB share at ${HAAS_MNT}

[Automount]
Where=${HAAS_MNT}

[Install]
WantedBy=multi-user.target
AMT

# ------------------ 4. USB image ------------------
echo "[bootstrap-haaspi] Ensuring ${USB_IMG} exists…"
if [ ! -f "${USB_IMG}" ]; then
  echo "[bootstrap-haaspi] Creating 8GB USB image at ${USB_IMG}…"
  sudo dd if=/dev/zero of="${USB_IMG}" bs=1G count=8 status=progress
  sudo mkfs.vfat -F 32 "${USB_IMG}"
  sudo chown "${ADMIN_USER}:${ADMIN_USER}" "${USB_IMG}"
else
  echo "[bootstrap-haaspi] ${USB_IMG} already exists; leaving it."
fi

sudo mkdir -p "${USB_MNT}"

# ------------------ 5. haas-sync.sh ------------------
# echo "[bootstrap-haaspi] Installing /home/${ADMIN_USER}/haas-sync.sh…"
sudo bash -c "cat > /home/${ADMIN_USER}/haas-sync.sh" << 'SYNC'
!/usr/bin/env bash
set -euo pipefail

LOG=/var/log/haas-sync.log

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
  echo "[$(timestamp)] haas-sync: $*" | tee -a "$LOG"
}

# --------- SELECT SHARE ROOT BY HOSTNAME ---------
HOSTNAME="$(hostname)"

case "$HOSTNAME" in
  HAAS120|HAAS121|HAAS122|HAAS123)
    SHARE_ROOT="/mnt/haasshare/Master Proven Prg/Mill/120-123 new 8-22"
    ;;
  *)
    log "WARNING: Unknown hostname '$HOSTNAME', defaulting SHARE_ROOT to mill 120-123 path."
    SHARE_ROOT="/mnt/haasshare/Master Proven Prg/Mill/120-123 new 8-22"
    ;;
esac

log "Using SHARE_ROOT='$SHARE_ROOT' for hostname '$HOSTNAME'."
log "start"

# Sanity checks
if [ ! -f "$USB_IMG" ]; then
  log "ERROR: $USB_IMG does not exist; aborting."
  exit 1
fi

# Ensure SMB share is mounted via automount
if ! mountpoint -q /mnt/haasshare; then
  log "Forcing SMB automount by listing /mnt/haasshare..."
  if ! ls /mnt/haasshare >/dev/null 2>&1; then
    log "ERROR: Unable to access /mnt/haasshare; aborting sync."
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

sudo chmod +x /home/${ADMIN_USER}/haas-sync.sh
sudo chown ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/haas-sync.sh

# ------------------ 6. systemd units ------------------
echo "[bootstrap-haaspi] Writing haas-sync.service and haas-sync.timer…"

sudo bash -c "cat > /etc/systemd/system/haas-sync.service" << 'SRV'
[Unit]
Description=Sync SMB share to local USB image and attach RW (g_mass_storage)
After=network-online.target mnt-haasshare.automount
Wants=network-online.target

[Service]
Type=oneshot
User=root
Group=root
ExecStart=/usr/bin/flock -n /run/lock/haas-sync.lock /home/admin/haas-sync.sh
Nice=10

[Install]
WantedBy=multi-user.target
SRV

sudo bash -c "cat > /etc/systemd/system/haas-sync.timer" << 'TMR'
[Unit]
Description=Periodic sync of Haas SMB share to USB image

[Timer]
OnBootSec=30s
OnUnitActiveSec=600s
Unit=haas-sync.service

[Install]
WantedBy=timers.target
TMR

# ------------------ 7. Bash helpers ------------------
echo "[bootstrap-haaspi] Ensuring HaasPi helpers (hsync, status, fix, off) are present in ~/.bashrc…"

BASHRC="/home/${ADMIN_USER}/.bashrc"

# Remove any existing HaasPi helper block (old or new) to avoid duplicates
sudo sed -i '/# --- HaasPi helpers BEGIN ---/,/# --- HaasPi helpers END ---/d' "${BASHRC}" 2>/dev/null || true
sudo sed -i '/# BEGIN HAASPI HELPERS/,/# END HAASPI HELPERS/d' "${BASHRC}" 2>/dev/null || true

# Append a single canonical helper block
sudo bash -c "cat >> '${BASHRC}'" << 'BRC'

# --- HaasPi helpers BEGIN ---
alias haas-sync='sudo systemctl start haas-sync.service'
alias hsync='haas-sync'

status() {
  echo "=== haas-sync.service ==="
  systemctl status haas-sync.service --no-pager
  echo
  echo "=== haas-sync.timer ==="
  systemctl status haas-sync.timer --no-pager
  echo
  echo "=== last 20 lines of /var/log/haas-sync.log ==="
  sudo tail -n 20 /var/log/haas-sync.log || true
}

fix() {
  echo "[fix] Checking CIFS automount…"
  systemctl status mnt-haasshare.automount --no-pager || true
  echo
  echo "[fix] Checking mount unit…"
  systemctl status mnt-haasshare.mount --no-pager || true
  echo
  echo "[fix] Forcing one sync run…"
  sudo systemctl start haas-sync.service
}

off() {
  echo "Shutting down Pi in 5 seconds…"
  sleep 5
  sudo shutdown -h now
}
# --- HaasPi helpers END ---

BRC

# ------------------ 8. Enable units & initial sync ------------------
echo "[bootstrap-haaspi] Reloading systemd and enabling units…"
sudo systemctl daemon-reload
sudo systemctl enable mnt-haasshare.automount haas-sync.timer >/dev/null

echo "[bootstrap-haaspi] Starting automount and timer…"
sudo systemctl start mnt-haasshare.automount
sudo systemctl start haas-sync.timer

echo "[bootstrap-haaspi] Forcing one initial sync…"
sudo systemctl start haas-sync.service || true

echo "[bootstrap-haaspi] Done. You may want to 'exec bash' or log out/in to pick up new helpers."
source ~/.bashrc
echo "[bootstrap-haaspi] Finished."