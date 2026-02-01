#!/usr/bin/env sh
set -eu

# Zed diagnostics collection script
# Usage: ./collect-zed-diagnostics.sh [output-dir]
# Example: ./collect-zed-diagnostics.sh /tmp/zed-diag

OUTPUT_DIR="${1:-$HOME/zed-diagnostics-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/files"

info() {
    printf '%s\n' "$*" | tee -a "$OUTPUT_DIR/summary.txt" >/dev/null
}

cmd() {
    printf '\n$ %s\n' "$*" >> "$OUTPUT_DIR/commands.log"
    sh -c "$*" >> "$OUTPUT_DIR/commands.log" 2>&1 || true
}

copy_if_exists() {
    src="$1"
    dest="$2"
    if [ -e "$src" ]; then
        cp -a "$src" "$dest"
        info "Collected: $src"
    else
        info "Missing: $src"
    fi
}

info "Zed diagnostics collection started: $(date)"
info "Output directory: $OUTPUT_DIR"
info "zed version: $(zed --version 2>/dev/null || echo not_found)"
info "zedit version: $(zedit --version 2>/dev/null || echo not_found)"

# Basic system info
cmd "uname -a"
cmd "id"
cmd "whoami"
cmd "echo \"SHELL=$SHELL\""
cmd "env | sort"

# Zed binaries and versions
cmd "command -v zed || true"
cmd "command -v zedit || true"
cmd "which zed || true"
cmd "which zedit || true"
cmd "zed --version || true"
cmd "zedit --version || true"

# Portage package info (if available)
cmd "equery list app-editors/zed || true"
cmd "equery meta app-editors/zed || true"

# Paths and ownership checks
cmd "ls -ld ~/.config/zed ~/.local/share/zed ~/.local/share/zed/logs || true"
cmd "find ~/.config/zed ~/.local/share/zed -user root -print 2>/dev/null || true"

# Settings and config files
copy_if_exists "$HOME/.config/zed/settings.json" "$OUTPUT_DIR/files/settings.json"
copy_if_exists "$HOME/.config/zed/keymap.json" "$OUTPUT_DIR/files/keymap.json"

# Zed logs
copy_if_exists "$HOME/.local/share/zed/logs/Zed.log" "$OUTPUT_DIR/files/Zed.log"
copy_if_exists "$HOME/.local/share/zed/logs/telemetry.log" "$OUTPUT_DIR/files/telemetry.log"

# Recent Zed log tail
cmd "tail -n 300 ~/.local/share/zed/logs/Zed.log 2>/dev/null || true"

# Desktop entries
copy_if_exists "$HOME/.local/share/applications/dev.zed.Zed.desktop" "$OUTPUT_DIR/files/dev.zed.Zed.desktop"
copy_if_exists "$HOME/.local/share/applications/dev.zed.Zed-Preview.desktop" "$OUTPUT_DIR/files/dev.zed.Zed-Preview.desktop"

# Print settings timestamp if present
cmd "stat ~/.config/zed/settings.json 2>/dev/null || true"

zed_ver="$(zed --version 2>/dev/null || echo not_found)"
zedit_ver="$(zedit --version 2>/dev/null || echo not_found)"
safe_zed_ver="$(printf '%s' "$zed_ver" | tr ' /' '__' | tr -cd 'A-Za-z0-9._-')"
safe_zedit_ver="$(printf '%s' "$zedit_ver" | tr ' /' '__' | tr -cd 'A-Za-z0-9._-')"
tarball="${OUTPUT_DIR}-zed-${safe_zed_ver}-zedit-${safe_zedit_ver}.tar.gz"
tar -czf "$tarball" -C "$(dirname "$OUTPUT_DIR")" "$(basename "$OUTPUT_DIR")"
info "Done. Collected diagnostics in: $OUTPUT_DIR"
info "Tarball: $tarball"
