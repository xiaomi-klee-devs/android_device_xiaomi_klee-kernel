#!/bin/bash

set -e

# Debug/helper functions
info() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

show_help() {
    cat <<EOF
Usage: $0 ROOT_DIR

This script copies kernel components and modules from the build output directory
into the flat kernel structure expected by the device tree:

  images/Image.lz4
  images/mt6899.dtb
  images/dtbo.img
  headers/kernel-uapi-headers.tar.gz
  modules/
    modules.load.system
    modules.load.vendor
    modules.load.vendor_ramdisk
    modules.load.recovery
    *.ko

Arguments:
  ROOT_DIR - Path to the root directory containing build outputs
EOF
}

# Validate input
if [ $# -ne 1 ]; then
    error "Please provide the root directory as an argument"
    show_help
    exit 1
fi

ROOT_DIR="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"

# Config paths
DIST_DIR="${ROOT_DIR}/out/dist/kernel_device_modules-6.6/mgk_64_k66_kernel_aarch64.user"
MTK_DIST_DIR="${ROOT_DIR}/out/dist/kernel_device_modules-6.6/mgk_64_k66.user"
CUSTOMER_MODULES_DIR="${ROOT_DIR}/out/dist/kernel_device_modules-6.6/mgk_64_k66_customer_modules_install.user"
MERGED_UAPI_DIR="${ROOT_DIR}/out/dist/kernel_device_modules-6.6/mgk_64_k66_merged_uapi_headers.user"
CLANG_VERISON=clang-r510928
STRIP_BIN="${ROOT_DIR}/prebuilts/clang/host/linux-x86/${CLANG_VERISON}/bin/llvm-strip"

# Validate directories exist
for dir in "$DIST_DIR" "$MTK_DIST_DIR" "$CUSTOMER_MODULES_DIR"; do
    if [ ! -d "$dir" ]; then
        error "Directory not found: $dir"
        exit 1
    fi
done

# Validate strip binary exists
if [ ! -x "$STRIP_BIN" ]; then
    error "Strip binary not found or not executable: $STRIP_BIN"
    exit 1
fi

cd "$SCRIPT_DIR"

# Kernel operations
info "Copying kernel images..."
mkdir -p images headers
cp "$DIST_DIR/Image.lz4" images/ || error "Failed to copy Image.lz4"
chmod -x images/Image.lz4

# Copy merged UAPI headers
UAPI_TAR="$MERGED_UAPI_DIR/kernel-uapi-headers.tar.gz"
if [ -f "$UAPI_TAR" ]; then
    info "Copying UAPI headers..."
    cp "$UAPI_TAR" headers/ || error "Failed to copy kernel-uapi-headers.tar.gz"
else
    warn "Missing $UAPI_TAR, skipping UAPI headers"
fi

# Copy modules (flat)
info "Copying kernel modules to modules/..."
mkdir -p "$MODULES_DIR"
rm -f "$MODULES_DIR"/*.ko
find "$DIST_DIR" -type f -name '*.ko' -exec cp -f {} "$MODULES_DIR/" \;
find "$CUSTOMER_MODULES_DIR" -maxdepth 1 -type f -name '*.ko' -exec cp -f {} "$MODULES_DIR/" \;
find "$MTK_DIST_DIR" -type f -name '*.ko' -exec cp -f {} "$MODULES_DIR/" \;

# Strip the modules
info "Stripping debug symbols from modules..."
find "$MODULES_DIR" -maxdepth 1 -type f -name '*.ko' -exec "$STRIP_BIN" --strip-debug {} +

# Keep module load lists consistent with the modules we actually ship
info "Pruning module load lists..."
for l in "$MODULES_DIR"/modules.load.*; do
    [ -f "$l" ] || continue
    tmp="$(mktemp)"
    while IFS= read -r m || [ -n "$m" ]; do
        [ -z "$m" ] && continue
        [ -f "$MODULES_DIR/$m" ] && printf '%s\n' "$m" >> "$tmp"
    done < "$l"
    mv "$tmp" "$l"
done

# DTB / DTBO
info "Generating DTB & DTBO images..."
MKDTIMG="${ROOT_DIR}/prebuilts/kernel-build-tools/linux-x86/bin/mkdtimg"
if [ ! -x "$MKDTIMG" ]; then
    MKDTIMG="$(command -v mkdtimg || true)"
fi
if [ -z "$MKDTIMG" ]; then
    warn "mkdtimg not found, skipping DTB/DTBO"
else
    DT_DIR="${MTK_DIST_DIR}/mediatek"
    mkdir -p images
    if [ -f "$DT_DIR/xiaomi_mt6899_common.dtb" ]; then
        "$MKDTIMG" create images/mt6899.dtb --page_size=2048 "$DT_DIR/xiaomi_mt6899_common.dtb" >/dev/null \
            && info "Wrote images/mt6899.dtb" \
            || error "Failed to create images/mt6899.dtb"
    else
        warn "Missing $DT_DIR/xiaomi_mt6899_common.dtb, keeping existing images/mt6899.dtb"
    fi
    if [ -f "$DT_DIR/klee.dtb" ]; then
        "$MKDTIMG" create images/dtbo.img --page_size=2048 "$DT_DIR/klee.dtb" >/dev/null \
            && info "Wrote images/dtbo.img" \
            || error "Failed to create images/dtbo.img"
    else
        warn "Missing $DT_DIR/klee.dtb, keeping existing images/dtbo.img"
    fi
fi

info "Operation completed successfully."
