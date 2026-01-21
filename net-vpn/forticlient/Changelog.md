# Changelog

## Version 7.4.5.1835 (2024-12-10)

### Added
- **New binaries:**
  - `certd` - Certificate daemon
  - `edrcomm` - EDR communication component
  - `fctdns` - DNS component
  - `firewall` - Firewall component
  - `FortiGuardAgent` - FortiGuard agent
  - `iked` - IKE daemon
  - `webfilter` - Web filtering component

- **New libraries:**
  - `libcertd.so` - Certificate library
  - `legacy.so` - Legacy support library

- **New helper scripts:**
  - `start-fortitray-launcher.sh` - Fortitray launcher startup script
  - `stop-forticlient.sh` - FortiClient stop script
  - `unlock-gui.sh` - GUI unlock script

- **New configuration/data files:**
  - `TLS_whitelist.json` - TLS whitelist configuration
  - `wf_intercepted_apps.json` - Web filter intercepted applications
  - `icdb` - IC database
  - `isdb_app.txt` - ISDB application list
  - `isdb_map.dat` - ISDB mapping data
  - `exe.manifest` - Executable manifest
  - `.acl` - Access control list

- **TPM2 support:**
  - New `tpm2/` directory structure
  - `tpm2/bin/tpm2` - TPM2 tools binary
  - `tpm2/lib/pkcs11.so` - PKCS#11 library for TPM2
  - TPM2-TSS FAPI configuration profiles (ECCP256SHA256, ECCP384SHA384, RSA2048SHA256, RSA3072SHA384)

### Changed
- **GUI structure refactored:**
  - Moved from nested `opt/forticlient/gui/FortiClient-linux-x64/` to flat `opt/forticlient/gui/`
  - Updated all GUI-related file paths accordingly
  - `libvulkan.so` renamed to `libvulkan.so.1`

- **Binary consolidation:**
  - `fortivpn` functionality merged into `vpn` binary (symlink maintained for backward compatibility)
  - `update_tls` functionality merged into `update` binary

- **Updated QA variables:**
  - Added new binaries to `QA_PREBUILT` list
  - Updated `QA_FLAGS_IGNORED` for new GUI structure
  - Added TPM2 binaries to QA lists

### Removed
- **Bash completion support:**
  - Removed `bash-completion-r1` inherit
  - Removed bash completion file installation (files no longer shipped in package)

- **Deprecated binaries:**
  - `update_tls` (merged into `update`)
  - `fortivpn` (replaced by `vpn`, symlink preserved)

- **GUI structure:**
  - Removed `swiftshader/` subdirectory (files moved to parent directory or removed)

### Technical Details
- Updated copyright year to 2024
- Version bump from 7.0.13.0376 to 7.4.5.1835
- Maintained compatibility with existing symlinks and directory structure
- All dependencies remain unchanged

---

## Version 7.0.13.0376 (2023)

Initial version in overlay.