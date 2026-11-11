#!/bin/bash

set -e

# Debug/helper functions
info() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

show_help() {
    cat <<EOF
Usage: $0 ROOT_DIR

This script copies kernel components and modules from the build output directory.

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

# Config paths
DIST_DIR="${ROOT_DIR}/out/dist/kernel_device_modules-6.6/mgk_64_k66_kernel_aarch64.user"
MTK_DIST_DIR="${ROOT_DIR}/out/dist/kernel_device_modules-6.6/mgk_64_k66.user"
CUSTOMER_MODULES_DIR="${ROOT_DIR}/out/dist/kernel_device_modules-6.6/mgk_64_k66_customer_modules_install.user"
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

# Create target directories if they don't exist
for TARGET in system_dlkm vendor_dlkm vendor_ramdisk; do
    mkdir -p "$TARGET"
done

# Kernel operations
info "Copying kernel images..."
cp "$DIST_DIR/Image.lz4" ./ || error "Failed to copy Image.lz4"
chmod -x Image.lz4

# Copy Modules
for TARGET in system_dlkm vendor_dlkm vendor_ramdisk; do
    info "Copying GKI modules to $TARGET..."
    find "$DIST_DIR" -type f -name '*.ko' -exec cp {} "$TARGET/" \;
    cp $CUSTOMER_MODULES_DIR/* $TARGET
    find "$MTK_DIST_DIR" -type f -name '*.ko' -exec cp {} "$TARGET/" \;
done

# Remove unused modules
info "Running git clean..."
git clean -f system_dlkm/ >/dev/null
git clean -f vendor_dlkm/ >/dev/null
git clean -f vendor_ramdisk/ >/dev/null

# Restore specific files
# FILES_TO_RESTORE=(
#     # Missing front camera
#     vendor_dlkm/camera_dpe_isp7sp.ko
#     vendor_dlkm/camera_eeprom_v4l2.ko
#     vendor_dlkm/imgsensor-glue.ko
#     vendor_dlkm/imgsensor.ko
#     vendor_dlkm/mtk_imgsys_cmdq.ko
#     vendor_dlkm/mtk_imgsys_isp7sp.ko
#     # I honestly don't know
#     vendor_ramdisk/rpmb-mtk.ko
#     vendor_ramdisk/ufs-mediatek-dbg.ko
#     vendor_ramdisk/ufs-mediatek-mod.ko
# )
# info "Restoring tracked files..."
# for f in "${FILES_TO_RESTORE[@]}"; do
#      git restore "$f" || warn "Failed to restore $f"
# done

# Strip the modules
info "Stripping debug symbols from modules..."
find . -type f -name '*.ko' -exec "$STRIP_BIN" --strip-debug {} +

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
    mkdir -p dtb
    if [ -f "$DT_DIR/xiaomi_mt6899_common.dtb" ]; then
        "$MKDTIMG" create dtb/mt6899.dtb --page_size=2048 "$DT_DIR/xiaomi_mt6899_common.dtb" >/dev/null \
            && info "Wrote dtb/mt6899.dtb" \
            || error "Failed to create dtb/mt6899.dtb"
    else
        warn "Missing $DT_DIR/xiaomi_mt6899_common.dtb, keeping existing dtb/mt6899.dtb"
    fi
    if [ -f "$DT_DIR/klee.dtb" ]; then
        "$MKDTIMG" create dtbo.img --page_size=2048 "$DT_DIR/klee.dtb" >/dev/null \
            && info "Wrote dtbo.img" \
            || error "Failed to create dtbo.img"
    else
        warn "Missing $DT_DIR/klee.dtb, keeping existing dtbo.img"
    fi
fi

info "Operation completed successfully."
