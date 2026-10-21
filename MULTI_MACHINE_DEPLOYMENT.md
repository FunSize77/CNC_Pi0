# Multi-Machine Deployment Guide

This guide describes deploying one Raspberry Pi USB sync device per CNC machine. Configure each Pi with its own hostname and the share path for that machine.

## Per-Pi setup

1. Install Raspberry Pi OS and enable network access and SSH.
2. Copy the project files to the Pi and run the bootstrap script:

   ```bash
   ./bootstrap-cncpi_l.sh
   ```

3. Configure the SMB endpoint in `bootstrap-cncpi_l.sh` using the `SMB_SERVER` and `SMB_SHARE` values near the top of the script. Enter your own SMB username and password in `/etc/samba/credentials-cnc`.
4. Set the sync script's hostname and share path:

   ```bash
   ./configure-machine.sh "$(hostname)" /mnt/cncshare/programs
   ```

   Replace `/mnt/cncshare/programs` with the absolute path to this machine's CNC program directory.

5. Verify the configuration and run a manual sync:

   ```bash
   sudo systemctl daemon-reload
   hsync
   status
   ```

Repeat these steps for each Pi, using the appropriate hostname and share directory. Do not copy a configured credentials file or machine-specific sync configuration between devices.

## Network and share requirements

- Each Pi must be able to reach the SMB server and share configured in the bootstrap script.
- Create a credentials file readable only by root and containing the SMB account used for that share.
- Confirm `/mnt/cncshare` is mounted and that the configured `SHARE_ROOT` directory exists before enabling automatic sync.
- Configure Wi-Fi interactively so the passphrase is not included in shell history:

  ```bash
  sudo nmcli --ask device wifi connect "SSID"
  ```

## Validation

On each Pi:

```bash
hostname
ls /mnt/cncshare
sudo systemctl list-timers | grep cnc-sync
sudo tail -n 50 /var/log/cnc-sync.log
```

Confirm the CNC can see the USB device and that the correct program directory is synchronized before using the device in production.

See [DEPLOYMENT.md](cnc-pi0-usb-sync/docs/DEPLOYMENT.md) for the installation and troubleshooting details.
