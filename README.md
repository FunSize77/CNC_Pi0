# HaasPi0 - Raspberry Pi USB Wi-Fi Sync for CNC Machines

Turn a Raspberry Pi Zero 2W into a **network-synced USB stick** for Haas CNC machines. The Pi appears as a USB flash drive to the CNC while automatically syncing with your network share over Wi-Fi.

## Features

- 🔄 **Two-way sync** between CNC and network share
- 📡 **WiFi connectivity** - no need for physical file transfers
- 🔒 **Safety protections** - prevents accidental deletion of network files
- ⚡ **Smart syncing** - only syncs when changes detected
- 🛠️ **Easy management** - simple bash commands for all operations
- 🎯 **Multi-machine support** - pre-configured for haas030, haas120, haas122

## Quick Start

### 1. Prepare Your Pi

- Flash **Raspberry Pi OS 64-bit** (Bookworm or newer) to your Raspberry Pi Zero 2W
- Connect to WiFi and enable SSH
- Create user `admin` if not present

### 2. Install on Pi

```bash
# Copy project files to your Pi
scp -r . admin@<pi-hostname>:~/haaspi0/

# SSH into the Pi
ssh admin@<pi-hostname>

# Run installation
cd ~/haaspi0
./bootstrap-haaspi_l.sh
```

### 3. Configure for Your Machine

```bash
# For lathe 030:
./configure-machine.sh haas030

# For mills 120-123:
./configure-machine.sh haas120
./configure-machine.sh haas122
```

### 4. You're Done!

The Pi now automatically syncs every 10 minutes. Plug it into your CNC's USB port and it appears as a USB drive.

## Usage Commands

After installation, these commands are available:

| Command | Description |
|---------|-------------|
| `hsync` or `haas-sync` | Manually trigger a sync |
| `status` | Show service status and recent logs |
| `off` | Safely shut down the Pi |
| `fix` | Repair utility for common issues |

## How It Works

```
Network Share (WiFi) ←→ Raspberry Pi ←→ CNC Machine (USB)
   //Weld-KC01            /piusb.bin        USB Flash Drive
```

1. **Pi boots** → Appears as USB flash drive to CNC
2. **Every 10 min** → Checks network share for changes, syncs if needed
3. **Every 1 hour** → Full sync to capture CNC-side changes
4. **Two-way** → Changes flow both directions with safety checks

## Project Structure

```
HaasPi0/
├── bootstrap-haaspi_l.sh          # Automated installation script
├── configure-machine.sh           # Machine configuration helper
├── MULTI_MACHINE_DEPLOYMENT.md   # Multi-machine deployment guide
├── CHANGES.md                     # Change log
├── haas-pi0-usb-sync/
│   ├── scripts/haas-sync          # Main sync script
│   ├── systemd/                   # Service and timer units
│   ├── docs/DEPLOYMENT.md         # Detailed deployment guide
│   └── README.md                  # Technical documentation
├── haas_pi_0_docs.md             # Comprehensive project documentation
├── active_check.ps1               # Network connectivity checker (Windows)
└── keepalive.sh                   # USB keepalive configuration
```

## Machine Configurations

| Machine | Type  | Share Path |
|---------|-------|-----------|
| haas030 | Lathe | `/mnt/haasshare/Master Proven Prg/Lathe/` |
| haas120 | Mill  | `/mnt/haasshare/Master Proven Prg/Mill/120-123 new 8-22` |
| haas122 | Mill  | `/mnt/haasshare/Master Proven Prg/Mill/120-123 new 8-22` |

## Documentation

- 📖 **[MULTI_MACHINE_DEPLOYMENT.md](MULTI_MACHINE_DEPLOYMENT.md)** - Deploy to multiple machines (haas030, haas120, haas122)
- 📖 **[haas-pi0-usb-sync/docs/DEPLOYMENT.md](haas-pi0-usb-sync/docs/DEPLOYMENT.md)** - Detailed installation and troubleshooting
- 📖 **[haas_pi_0_docs.md](haas_pi_0_docs.md)** - Complete system documentation
- 📖 **[CHANGES.md](CHANGES.md)** - Recent changes and fixes

## Requirements

### Hardware
- Raspberry Pi Zero 2W (or compatible with USB OTG)
- MicroSD card (128GB recommended, Class 10)
- USB cable (data + power to CNC)

### Software
- Debian Trixie x64 (Raspberry Pi OS)
- Network access to SMB share: `//Weld-KC01/cnc programs`

### Network
- WiFi connectivity
- Access to Windows file server (Weld-KC01 at 192.168.126.128)

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
sudo journalctl -u mnt-haasshare.mount
```

### USB not appearing on CNC
```bash
lsmod | grep g_mass_storage
sudo systemctl restart usb-gadget.service
```

### Sync errors
```bash
sudo tail -n 100 /var/log/haas-sync.log
fix  # Run the repair utility
```

See [DEPLOYMENT.md](haas-pi0-usb-sync/docs/DEPLOYMENT.md) for detailed troubleshooting.

## Contributing

This is a specialized project for Weld Racing's CNC machines. If you're adapting it for your own use, you'll need to modify:

1. Network share path and credentials
2. Machine hostnames
3. Share directory structure

## License

Internal project for Weld Racing CNC operations.

## Support

For issues or questions, check:
1. [DEPLOYMENT.md](haas-pi0-usb-sync/docs/DEPLOYMENT.md) - Detailed troubleshooting
2. [MULTI_MACHINE_DEPLOYMENT.md](MULTI_MACHINE_DEPLOYMENT.md) - Multi-machine setup
3. Logs at `/var/log/haas-sync.log`

---

**Status**: ✅ Production Ready - Currently deployed on haas030, haas120, haas122
