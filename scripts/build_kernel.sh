#!/usr/bin/env bash
# scripts/build_kernel.sh
set -euo pipefail

ENABLE_NOMOUNT=${ENABLE_NOMOUNT:-false}
ENABLE_NET_OPTS=${ENABLE_NET_OPTS:-false}
BASE_VER=${BASE_VER:-}

echo "=== Initializing Execution Engine ==="

cd kernel_workspace
mkdir -p ../out out/dist

# 🚨 【强行注入虚拟驱动 & 关闭 BTF & 关闭外部证书依赖】
echo ">>> Forcing VirtIO Drivers, Disabling BTF and Trusted Keys..."
CONFIG_FILE="common/arch/arm64/configs/gki_defconfig"
echo "CONFIG_VIRTIO=y" >> $CONFIG_FILE
echo "CONFIG_VIRTIO_PCI=y" >> $CONFIG_FILE
echo "CONFIG_VIRTIO_BLK=y" >> $CONFIG_FILE
echo "CONFIG_VIRTIO_NET=y" >> $CONFIG_FILE
echo "CONFIG_DRM=y" >> $CONFIG_FILE
echo "CONFIG_VIRTIO_GPU=y" >> $CONFIG_FILE
echo "CONFIG_DEVTMPFS=y" >> $CONFIG_FILE

echo "# CONFIG_DEBUG_INFO_BTF is not set" >> $CONFIG_FILE
echo "# CONFIG_DEBUG_INFO_BTF_MODULES is not set" >> $CONFIG_FILE
echo "# CONFIG_DEBUG_INFO is not set" >> $CONFIG_FILE
echo "CONFIG_DEBUG_INFO_NONE=y" >> $CONFIG_FILE

echo "# CONFIG_SYSTEM_TRUSTED_KEYS is not set" >> $CONFIG_FILE
echo "# CONFIG_SYSTEM_REVOCATION_KEYS is not set" >> $CONFIG_FILE

# 🚨 【伪造假证书】双管齐下
mkdir -p common/debian
touch common/debian/canonical-certs.pem
touch common/debian/canonical-revoked-certs.pem

# 🚨 【精准修复被误伤的八进制】只改该改的，绝不瞎搞！
echo ">>> Fixing illegal octal constants in slab.h (08->18, 09->19)..."
sed -i 's/return 08/return 18/g' common/include/linux/slab.h || true
sed -i 's/return 09/return 19/g' common/include/linux/slab.h || true
find common -name "slab.h" -exec sed -i 's/return 08/return 18/g; s/return 09/return 19/g' {} + || true

echo ">>> Fixing illegal octal number in sigreturn.S (039->139)..."
sed -i 's/#039/#139/g' common/arch/arm64/kernel/vdso/sigreturn.S || true
find common/arch/arm64/kernel/vdso -name "sigreturn.S" -exec sed -i 's/#039/#139/g' {} + || true

# 🚨 【环境变量修复】
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

# Build method 
if [ "$BASE_VER" != "5.10" ] && [ -f "tools/bazel" ]; then
    echo ">>> Modern Kleaf/Bazel ecosystem detected for $BASE_VER..."
    TRIM_FLAGS=""
    if [ "$BASE_VER" = "5.15" ]; then
        echo "  -> 5.15 detected. Relying on physical Bazel dictionary patch (omitting --notrim)..."
    else
        TRIM_FLAGS="--notrim"
    fi
    tools/bazel run --config=stamp $TRIM_FLAGS \
      --action_env=SOURCE_DATE_EPOCH="$OFFICIAL_DATE" \
      --action_env=STABLE_BUILD_VERSION="-g$OFFICIAL_HASH" \
      --action_env=KLEAF_KERNEL_BUILD_VERSION="-g$OFFICIAL_HASH" \
      --action_env=KLEAF_SKIP_ABI_CHECKS=true \
      --action_env=KLEAF_USER=android-build \
      //common:kernel_aarch64_dist \
      -- \
      --destdir=out/dist
else
    echo ">>> Legacy Hermetic Make ecosystem detected (5.10 or fallback)..."
    mkdir -p out/dist
    export DIST_DIR="out/dist"
    export KERNEL_DIR="common"
    export BUILD_CONFIG="common/build.config.gki.aarch64"
    export SOURCE_DATE_EPOCH="$OFFICIAL_DATE"
    export EXTRA_LINUX_VERSION="-g${OFFICIAL_HASH}"
    
    if [ -f "build/build.sh" ]; then
        echo "[+] Invoking build/build.sh..."
        bash build/build.sh
    else
        echo "[-] ERROR: Legacy build/build.sh orchestrator not found!" >&2
        exit 1
    fi
fi

IMAGE_PATH="$(find out/dist -type f -name 'Image' -print -quit)"
if [ -z "${IMAGE_PATH}" ] || [ ! -f "${IMAGE_PATH}" ]; then
  echo "[-] No compilation Image produced!" >&2
  exit 1
fi

echo ">>> Selected Image: ${IMAGE_PATH}"
cp -f "${IMAGE_PATH}" ../out/Image

echo ">>> Extracting kernel runtime version string..."
KERNEL_VERSION_STRING=$(strings ../out/Image | grep -E "Linux version [0-9]" | head -n 1 || true)
if [ -z "$KERNEL_VERSION_STRING" ]; then
    KERNEL_VERSION_STRING=$(strings ../out/Image | grep -i "Linux version" | head -n 1 || true)
fi
if [ -n "$KERNEL_VERSION_STRING" ]; then
    echo "    $KERNEL_VERSION_STRING"
else
    echo "    [!] Notice: Could not read raw banner string directly from compiled Image binary."
fi

cd ..
echo ">>> Build execution loop completed"
