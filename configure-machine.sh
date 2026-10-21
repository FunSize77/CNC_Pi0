#!/usr/bin/env bash
#
# configure-machine.sh - Configure cnc-sync for a specific machine
#
# Usage: ./configure-machine.sh <machine-name> <absolute-share-path>

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <machine-name> <absolute-share-path>"
  exit 1
fi

MACHINE="$1"
SHARE_PATH="$2"
SYNC_SCRIPT="/usr/local/sbin/cnc-sync"

if [ ! -f "$SYNC_SCRIPT" ]; then
  echo "ERROR: $SYNC_SCRIPT not found!"
  echo "Please run bootstrap-cncpi_l.sh first."
  exit 1
fi

echo "Configuring cnc-sync for machine: $MACHINE"

if [[ ! "$MACHINE" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: Machine name may contain only letters, numbers, dots, underscores, and hyphens."
  exit 1
fi

if [[ "$SHARE_PATH" != /* || "$SHARE_PATH" == *$'\n'* ]]; then
  echo "ERROR: Share path must be an absolute path on one line."
  exit 1
fi

echo "  Machine: $MACHINE"
echo "  Share path: $SHARE_PATH"
echo ""

# Create a temporary file with the changes
TEMP_FILE=$(mktemp)
cp "$SYNC_SCRIPT" "$TEMP_FILE"

printf -v QUOTED_MACHINE '%q' "$MACHINE"
printf -v QUOTED_SHARE_PATH '%q' "$SHARE_PATH"
QUOTED_MACHINE=${QUOTED_MACHINE//\\/\\\\}
QUOTED_MACHINE=${QUOTED_MACHINE//&/\\&}
QUOTED_MACHINE=${QUOTED_MACHINE//|/\\|}
QUOTED_SHARE_PATH=${QUOTED_SHARE_PATH//\\/\\\\}
QUOTED_SHARE_PATH=${QUOTED_SHARE_PATH//&/\\&}
QUOTED_SHARE_PATH=${QUOTED_SHARE_PATH//|/\\|}
sed -i "s|^CNC_HOSTNAME=.*|CNC_HOSTNAME=${QUOTED_MACHINE}|" "$TEMP_FILE"
sed -i "s|^SHARE_ROOT=.*|SHARE_ROOT=${QUOTED_SHARE_PATH}|" "$TEMP_FILE"

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
