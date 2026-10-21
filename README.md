# CNC Pi USB Wi-Fi Sync

Turn a Raspberry Pi Zero 2W into a **network-synced USB stick** for CNC machines. The Pi appears as a USB flash drive to the CNC while automatically syncing with your network share over Wi-Fi.

## Features

- 🔄 **Two-way sync** between CNC and network share
- 📡 **WiFi connectivity** - no need for physical file transfers
- 🔒 **Safety protections** - prevents accidental deletion of network files
- ⚡ **Smart syncing** - only syncs when changes detected
- 🛠️ **Easy management** - simple bash commands for all operations
- 🎯 **Machine-independent configuration** - set the hostname and share path for each installation

## Quick Start

### 1. Prepare Your Pi

- Flash **Raspberry Pi OS 64-bit** (Bookworm or newer) to your Raspberry Pi Zero 2W
- Connect to WiFi and enable SSH
- Create user `admin` if not present

### 2. Install on Pi

```bash
# Copy project files to your Pi
scp -r . admin@<pi-hostname>:~/cncpi0/

# SSH into the Pi
ssh admin@<pi-hostname>

# Run installation
cd ~/cncpi0
./bootstrap-cncpi_l.sh
```

### 3. Configure for Your Machine

```bash
./configure-machine.sh "$(hostname)" /mnt/cncshare/programs
```

### 4. You're Done!

The Pi now automatically syncs every 10 minutes. Plug it into your CNC's USB port and it appears as a USB drive.

## Usage Commands

After installation, these commands are available:

| Command | Description |
|---------|-------------|
| `hsync` or `cnc-sync` | Manually trigger a sync |
| `status` | Show service status and recent logs |
| `off` | Safely shut down the Pi |
| `fix` | Repair utility for common issues |

## How It Works

```
Network Share (WiFi) ←→ Raspberry Pi ←→ CNC Machine (USB)
   [SMB share]                           /piusb.bin        USB Flash Drive
```

1. **Pi boots** → Appears as USB flash drive to CNC
2. **Every 10 min** → Checks network share for changes, syncs if needed
3. **Every 1 hour** → Full sync to capture CNC-side changes
4. **Two-way** → Changes flow both directions with safety checks

## Project Structure

```
CNC-Pi-USB-Sync/
├── bootstrap-cncpi_l.sh          # Automated installation script
├── configure-machine.sh           # Machine configuration helper
├── MULTI_MACHINE_DEPLOYMENT.md   # Multi-machine deployment guide
├── CHANGES.md                     # Change log
├── cnc-pi0-usb-sync/
│   ├── scripts/cnc-sync          # Main sync script
│   ├── systemd/                   # Service and timer units
│   ├── docs/DEPLOYMENT.md         # Detailed deployment guide
│   └── README.md                  # Technical documentation
├── cnc_pi_0_docs.md             # Comprehensive project documentation
├── active_check.ps1               # Network connectivity checker (Windows)
└── keepalive.sh                   # USB keepalive configuration
```

## Documentation

- 📖 **[MULTI_MACHINE_DEPLOYMENT.md](MULTI_MACHINE_DEPLOYMENT.md)** - Configure and deploy to multiple machines
- 📖 **[cnc-pi0-usb-sync/docs/DEPLOYMENT.md](cnc-pi0-usb-sync/docs/DEPLOYMENT.md)** - Detailed installation and troubleshooting
- 📖 **[cnc_pi_0_docs.md](cnc_pi_0_docs.md)** - Complete system documentation
- 📖 **[CHANGES.md](CHANGES.md)** - Recent changes and fixes

## Requirements

### Hardware
- Raspberry Pi Zero 2W (or compatible with USB OTG)
- MicroSD card (128GB recommended, Class 10)
- USB cable (data + power to CNC)

### Software
- Debian Trixie x64 (Raspberry Pi OS)
- Network access to an SMB share configured for your environment

### Network
- WiFi connectivity
- Access to your configured file server

## Safety Features

The system includes multiple safety protections:

- **Recovery Mode** - If USB appears empty but share is full, restores from share
- **Delete Limits** - Maximum of 100 files deleted per sync
- **Two-way Protection** - Prevents accidental mass deletions
- **Error Handling** - Fails safely and logs all issues
- **USB Gadget Safety** - Won't modify image while exported to CNC

## Troubleshooting

### Pi not visible on network
```bash
nmcli device status
```

### Share not mounting
```bash
sudo journalctl -u mnt-cncshare.mount
```

### USB not appearing on CNC
```bash
lsmod | grep g_mass_storage
sudo systemctl restart usb-gadget.service
```

### Sync errors
```bash
sudo tail -n 100 /var/log/cnc-sync.log
fix  # Run the repair utility
```

See [DEPLOYMENT.md](cnc-pi0-usb-sync/docs/DEPLOYMENT.md) for detailed troubleshooting.

## Contributing

Configure these installation-specific values before syncing:

1. Network share path and credentials
2. Machine hostnames
3. Share directory structure

## License

This project is intended to be adapted to your CNC environment.

## Support

For issues or questions, check:
1. [DEPLOYMENT.md](cnc-pi0-usb-sync/docs/DEPLOYMENT.md) - Detailed troubleshooting
2. [MULTI_MACHINE_DEPLOYMENT.md](MULTI_MACHINE_DEPLOYMENT.md) - Multi-machine setup
3. Logs at `/var/log/cnc-sync.log`

---

**Status**: Configure and test in your environment before deployment.
