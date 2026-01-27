#!/bin/bash
set -euo pipefail

echo "=== Haas Pi keepalive configuration ==="

# Must be root
if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root, e.g.: sudo $0"
    exit 1
fi

BOOT_CONF="/boot/firmware/config.txt"
CMDLINE="/boot/firmware/cmdline.txt"

timestamp=$(date +%Y%m%d%H%M%S)

echo
echo "--- Backing up boot config files ---"
if [[ -f "$BOOT_CONF" ]]; then
    cp "$BOOT_CONF" "${BOOT_CONF}.bak.${timestamp}"
    echo "Backup created: ${BOOT_CONF}.bak.${timestamp}"
else
    echo "WARNING: $BOOT_CONF not found"
fi

if [[ -f "$CMDLINE" ]]; then
    cp "$CMDLINE" "${CMDLINE}.bak.${timestamp}"
    echo "Backup created: ${CMDLINE}.bak.${timestamp}"
else
    echo "WARNING: $CMDLINE not found"
fi

echo
echo "--- Ensuring USB gadget overlay (dwc2) in config.txt ---"
if [[ -f "$BOOT_CONF" ]]; then
    if grep -q '^dtoverlay=dwc2' "$BOOT_CONF"; then
        echo "dtoverlay=dwc2 already present in config.txt"
    else
        {
            echo ""
            echo "# Added by haas-keepalive.sh: enable USB gadget mode for Haas"
            echo "dtoverlay=dwc2,dr_mode=peripheral"
        } >> "$BOOT_CONF"
        echo "Added dtoverlay=dwc2,dr_mode=peripheral to config.txt"
    fi
fi

echo
echo "--- Disabling USB autosuspend in cmdline.txt ---"
if [[ -f "$CMDLINE" ]]; then
    if grep -q 'usbcore\.autosuspend' "$CMDLINE"; then
        echo "usbcore.autosuspend already set in cmdline.txt"
    else
        # cmdline.txt must remain a single line; append the parameter
        sed -i '1s/$/ usbcore.autosuspend=-1/' "$CMDLINE"
        echo "Appended 'usbcore.autosuspend=-1' to cmdline.txt"
    fi
fi

echo
echo "--- Disabling Wi-Fi power saving (NetworkManager if present) ---"
if command -v NetworkManager >/dev/null 2>&1 || systemctl list-unit-files | grep -q '^NetworkManager.service'; then
    mkdir -p /etc/NetworkManager/conf.d
    cat > /etc/NetworkManager/conf.d/wifi-powersave-off.conf <<EOF
[connection]
wifi.powersave = 2
EOF
    echo "Created /etc/NetworkManager/conf.d/wifi-powersave-off.conf (wifi.powersave = 2)"
else
    echo "NetworkManager not detected; skipping NM-specific config."
fi

echo
echo "--- Creating systemd service to disable Wi-Fi power save at boot ---"
IW_BIN="$(command -v iw || true)"

if [[ -n "$IW_BIN" ]]; then
    cat > /etc/systemd/system/wifi-powersave-off.service <<EOF
[Unit]
Description=Disable Wi-Fi power saving on wlan0
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=$IW_BIN dev wlan0 set power_save off

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable wifi-powersave-off.service

    echo "Created and enabled wifi-powersave-off.service using: $IW_BIN"
else
    echo "WARNING: 'iw' binary not found; cannot create Wi-Fi power-save service."
fi

echo
echo "=== Done. Reboot is recommended: sudo reboot ==="
