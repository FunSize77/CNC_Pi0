# Changes Summary - Multi-Machine Support

## Issues Fixed

### 1. **Alias Conflict with System Command**
- **Problem**: The `sync` alias was overriding the Linux `sync` command (used to flush file system buffers)
- **Solution**: Removed the `sync` alias, kept `hsync` and `cnc-sync` instead
- **Impact**: Users should use `hsync` or `cnc-sync` to trigger manual syncs

### 2. **Dependency Sequence**
- **Problem**: Services could be created even if `/piusb.bin` failed to create
- **Solution**: Added verification after `/piusb.bin` creation with exit on failure
- **Impact**: Bootstrap will fail fast if disk image creation fails

### 3. **Incorrect Path References**
- **Problem**: Final message referenced wrong path `/home/admin/cnc-sync.sh`
- **Solution**: Updated to correct path `/usr/local/sbin/cnc-sync`
- **Impact**: Users now get accurate instructions

### 4. **Machine Configuration Complexity**
- **Problem**: Manual editing required for each machine with different paths
- **Solution**: Created `configure-machine.sh` helper script
- **Impact**: Easy configuration with: `./configure-machine.sh cnc030`

## New Features

### 1. **configure-machine.sh Script**
Automated configuration for known machines:
- `cnc030` → Lathe share path
- `cnc120`, `cnc122` → Mill share path
- Interactive confirmation before applying changes
- Shows diff preview

### 2. **MULTI_MACHINE_DEPLOYMENT.md**
Comprehensive guide covering:
- Configuration for 3 machines (cnc030, cnc120, cnc122)
- Installation steps for each machine
- Verification checklist
- Troubleshooting guide
- Network share structure diagram

### 3. **Updated Documentation**
- README.md: Added reference to configure-machine.sh
- DEPLOYMENT.md: Already updated in previous commit
- All docs reference correct commands (hsync instead of sync)

## Deployment Workflow

For each machine (cnc030, cnc120, cnc122):

```bash
# 1. Copy files to Pi
scp -r cnc-pi0-usb-sync bootstrap-cncpi_l.sh configure-machine.sh admin@cnc030.local:~/

# 2. Run bootstrap
ssh admin@cnc030.local
./bootstrap-cncpi_l.sh

# 3. Configure for specific machine
./configure-machine.sh cnc030

# 4. Test
hsync
status
```

## Command Reference

| Old Command | New Command | Notes |
|-------------|-------------|-------|
| `sync` | `hsync` | Changed to avoid system command conflict |
| - | `cnc-sync` | Same as hsync, more explicit |
| `status` | `status` | ✓ No change (not a system command) |
| `off` | `off` | ✓ No change |
| `fix` | `fix` | ✓ No change |

## Files Modified

1. `bootstrap-cncpi_l.sh` - Fixed aliases, added verification, updated messages
2. `cnc-pi0-usb-sync/README.md` - Updated quick start instructions

## Files Added

1. `configure-machine.sh` - Machine configuration helper
2. `MULTI_MACHINE_DEPLOYMENT.md` - Multi-machine deployment guide
3. `CHANGES.md` - This file

## Testing Checklist

Before deploying to production:

- [ ] Bootstrap runs without errors
- [ ] /piusb.bin is created successfully
- [ ] cnc-sync script is installed to /usr/local/sbin/
- [ ] All systemd services are created
- [ ] Services are enabled and started
- [ ] configure-machine.sh correctly sets hostname and share path
- [ ] hsync command works (no conflict with system sync)
- [ ] status command shows service status
- [ ] USB gadget appears on CNC machine
- [ ] Sync logs show successful operations

## Machine-Specific Paths

| Machine | Type | Share Path |
|---------|------|-----------|
| cnc030 | Lathe | `/mnt/cncshare/Master Proven Prg/Lathe/` |
| cnc120 | Mill | `/mnt/cncshare/Master Proven Prg/Mill/120-123 new 8-22` |
| cnc122 | Mill | `/mnt/cncshare/Master Proven Prg/Mill/120-123 new 8-22` |
