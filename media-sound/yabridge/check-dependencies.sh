#!/bin/bash
# Helper script to check yabridge subproject dependencies
# Usage: ./check-dependencies.sh <path-to-yabridge-tarball-or-directory>

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <path-to-yabridge-tarball-or-directory>"
    echo ""
    echo "Examples:"
    echo "  $0 yabridge-5.1.1.tar.gz"
    echo "  $0 /path/to/extracted/yabridge-5.1.1/"
    exit 1
fi

INPUT="$1"
TEMP_DIR=""

# Function to clean up temporary directory
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# Check if input is a file or directory
if [ -f "$INPUT" ]; then
    echo "Extracting tarball..."
    TEMP_DIR=$(mktemp -d)
    tar -xzf "$INPUT" -C "$TEMP_DIR"
    # Find the yabridge directory (should be only one)
    YABRIDGE_DIR=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d -name "yabridge-*")
elif [ -d "$INPUT" ]; then
    YABRIDGE_DIR="$INPUT"
else
    echo "Error: Input is neither a file nor a directory"
    exit 1
fi

if [ ! -d "$YABRIDGE_DIR/subprojects" ]; then
    echo "Error: Could not find subprojects directory in $YABRIDGE_DIR"
    exit 1
fi

echo "Checking yabridge subproject dependencies..."
echo "==========================================="
echo ""

cd "$YABRIDGE_DIR/subprojects"

# Function to extract git info from wrap file
extract_wrap_info() {
    local wrap_file="$1"
    local name=$(basename "$wrap_file" .wrap)

    echo "[$name]"

    if [ ! -f "$wrap_file" ]; then
        echo "  WARNING: Wrap file not found!"
        echo ""
        return
    fi

    local url=$(grep "^url = " "$wrap_file" | cut -d'=' -f2- | xargs)
    local revision=$(grep "^revision = " "$wrap_file" | cut -d'=' -f2- | xargs)
    local clone_recursive=$(grep "^clone-recursive = " "$wrap_file" | cut -d'=' -f2- | xargs)

    echo "  URL: $url"
    echo "  Revision: $revision"
    if [ -n "$clone_recursive" ]; then
        echo "  Clone recursive: $clone_recursive"
        echo "  ⚠️  WARNING: This dependency uses submodules!"
    fi
    echo ""
}

# Check each dependency
extract_wrap_info "asio.wrap"
extract_wrap_info "bitsery.wrap"
extract_wrap_info "clap.wrap"
extract_wrap_info "function2.wrap"
extract_wrap_info "ghc_filesystem.wrap"
extract_wrap_info "tomlplusplus.wrap"
extract_wrap_info "vst3.wrap"

echo ""
echo "VST3 SDK Submodule Details"
echo "=========================="
echo ""

if [ -f "vst3.wrap" ]; then
    echo "The VST3 SDK uses git submodules that must be manually fetched."
    echo "To find the specific commit hashes for each submodule:"
    echo ""
    echo "1. Clone the VST3 SDK repository:"
    VST3_URL=$(grep "^url = " "vst3.wrap" | cut -d'=' -f2- | xargs)
    VST3_REV=$(grep "^revision = " "vst3.wrap" | cut -d'=' -f2- | xargs)
    echo "   git clone --depth=1 --recurse-submodules --branch $VST3_REV $VST3_URL vst3-temp"
    echo ""
    echo "2. Check the submodule commits:"
    echo "   cd vst3-temp"
    echo "   git submodule status"
    echo ""
    echo "3. Update the ebuild's src_prepare() with the commit hashes shown"
    echo ""
else
    echo "WARNING: vst3.wrap not found!"
fi

echo ""
echo "SRC_URI Generation"
echo "=================="
echo ""
echo "Add these to your ebuild's SRC_URI (verify URLs and create proper filenames):"
echo ""

for wrap in *.wrap; do
    if [ -f "$wrap" ]; then
        name=$(basename "$wrap" .wrap)
        url=$(grep "^url = " "$wrap" | cut -d'=' -f2- | xargs)
        revision=$(grep "^revision = " "$wrap" | cut -d'=' -f2- | xargs)

        # Try to construct a reasonable filename
        if [[ "$url" == *"github.com"* ]]; then
            repo_name=$(echo "$url" | sed 's/.*github.com\/[^\/]*\///' | sed 's/\.git$//')
            echo "  $url/archive/${revision}.tar.gz -> ${name}-VERSION.tar.gz"
        else
            echo "  # $name: $url @ $revision"
        fi
    fi
done

echo ""
echo "Done!"
