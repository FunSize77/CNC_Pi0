#!/usr/bin/env bash
#
# configure-machine.sh - Configure haas-sync for a specific machine
#
# Usage: ./configure-machine.sh <machine-name>
#   Example: ./configure-machine.sh haas030
#            ./configure-machine.sh haas120
#            ./configure-machine.sh haas122

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <machine-name>"
  echo ""
  echo "Examples:"
  echo "  $0 haas030   # for lathe 030"
  echo "  $0 haas120   # for mill 120-123"
  echo "  $0 haas122   # for mill 120-123"
  exit 1
fi

MACHINE="$1"
SYNC_SCRIPT="/usr/local/sbin/haas-sync"

if [ ! -f "$SYNC_SCRIPT" ]; then
  echo "ERROR: $SYNC_SCRIPT not found!"
  echo "Please run bootstrap-haaspi_l.sh first."
  exit 1
fi

echo "Configuring haas-sync for machine: $MACHINE"

# Define share paths for each machine
case "$MACHINE" in
  haas030)
    SHARE_PATH="/mnt/haasshare/Master Proven Prg/Lathe/"
    ;;
  haas120|haas121|haas122|haas123)
    SHARE_PATH="/mnt/haasshare/Master Proven Prg/Mill/120-123 new 8-22"
    ;;
  *)
    echo "ERROR: Unknown machine '$MACHINE'"
    echo "Known machines: haas030, haas120, haas121, haas122, haas123"
    echo ""
    echo "If this is a new machine, edit this script to add the share path,"
    echo "or manually edit $SYNC_SCRIPT to set:"
    echo "  HAAS_HOSTNAME=\"$MACHINE\""
    echo "  SHARE_ROOT=\"/mnt/haasshare/path/to/programs\""
    exit 1
    ;;
esac

echo "  Machine: $MACHINE"
echo "  Share path: $SHARE_PATH"
echo ""

# Create a temporary file with the changes
TEMP_FILE=$(mktemp)
cp "$SYNC_SCRIPT" "$TEMP_FILE"

# Update HAAS_HOSTNAME
sed -i "s/^HAAS_HOSTNAME=.*/HAAS_HOSTNAME=\"$MACHINE\"/" "$TEMP_FILE"

# Update SHARE_ROOT
# Escape forward slashes for sed
ESCAPED_PATH=$(echo "$SHARE_PATH" | sed 's/\//\\\//g')
sed -i "s/^SHARE_ROOT=.*/SHARE_ROOT=\"$SHARE_PATH\"   # <-- CHANGE THIS PATH/" "$TEMP_FILE"

# Show the diff
echo "Changes to be made:"
echo "-------------------"
diff -u "$SYNC_SCRIPT" "$TEMP_FILE" || true
echo "-------------------"
echo ""

read -p "Apply these changes? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  sudo cp "$TEMP_FILE" "$SYNC_SCRIPT"
  sudo chmod 755 "$SYNC_SCRIPT"
  echo "Configuration updated successfully!"
  echo ""
  echo "Next steps:"
  echo "  1. Verify with: sudo nano $SYNC_SCRIPT"
  echo "  2. Test with: hsync"
  echo "  3. Check logs with: status"
else
  echo "Configuration not applied."
fi

rm -f "$TEMP_FILE"
