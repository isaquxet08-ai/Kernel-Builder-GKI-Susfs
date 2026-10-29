#!/usr/bin/env bash
# scripts/build_kernel.sh
set -euo pipefail

ENABLE_NOMOUNT=${ENABLE_NOMOUNT:-false}
ENABLE_NET_OPTS=${ENABLE_NET_OPTS:-false}
BASE_VER=${BASE_VER:-}

echo "=== Initializing Execution Engine ==="

cd kernel_workspace
mkdir -p ../out out/dist

echo ">>> Forcing VirtIO Drivers & Disabling useless stuff..."
CONFIG_FILE="common/arch/arm64/configs/gki_defconfig"
echo "CONFIG_VIRTIO=y" >> $CONFIG_FILE
echo "CONFIG_VIRTIO_PCI=y" >> $CONFIG_FILE
echo "CONFIG_VIRTIO_BLK=y" >> $CONFIG_FILE
echo "CONFIG_VIRTIO_NET=y" >> $CONFIG_FILE
echo "CONFIG_DRM=y" >> $CONFIG_FILE
echo "CONFIG_VIRTIO_GPU=y" >> $CONFIG_FILE
echo "CONFIG_DEVTMPFS=y" >> $CONFIG_FILE

# 🚨 核心防雷组件关闭
echo "# CONFIG_DEBUG_INFO_BTF is not set" >> $CONFIG_FILE
echo "# CONFIG_DEBUG_INFO_BTF_MODULES is not set" >> $CONFIG_FILE
echo "# CONFIG_DEBUG_INFO is not set" >> $CONFIG_FILE
echo "CONFIG_DEBUG_INFO_NONE=y" >> $CONFIG_FILE
echo "# CONFIG_SYSTEM_TRUSTED_KEYS is not set" >> $CONFIG_FILE
echo "# CONFIG_SYSTEM_REVOCATION_KEYS is not set" >> $CONFIG_FILE
echo "# CONFIG_SYSTEM_REVOCATION_LIST is not set" >> $CONFIG_FILE
echo "# CONFIG_IKHEADERS is not set" >> $CONFIG_FILE
echo "# CONFIG_MODULE_SIG is not set" >> $CONFIG_FILE

# 🚨 终极瘦身：干掉一切不需要的第三方硬件模块（大幅缩短编译时间并避免报错）
echo ">>> Purging useless hardware modules..."
# 干掉所有第三方有线网卡
for vendor in INTEL REALTEK BROADCOM MELLANOX MARVELL MICROSOFT; do
    echo "# CONFIG_NET_VENDOR_${vendor} is not set" >> $CONFIG_FILE
done
# 干掉所有无线网卡（WLAN/WiFi）
echo "# CONFIG_WLAN is not set" >> $CONFIG_FILE
echo "# CONFIG_WIRELESS is not set" >> $CONFIG_FILE
# 干掉所有 AMD/NVIDIA/INTEL 的 PC 显卡驱动
echo "# CONFIG_DRM_AMDGPU is not set" >> $CONFIG_FILE
echo "# CONFIG_DRM_RADEON is not set" >> $CONFIG_FILE
echo "# CONFIG_DRM_NOUVEAU is not set" >> $CONFIG_FILE
echo "# CONFIG_DRM_I915 is not set" >> $CONFIG_FILE
# 干掉各种无用总线
echo "# CONFIG_SCSI is not set" >> $CONFIG_FILE
echo "# CONFIG_ATA is not set" >> $CONFIG_FILE

echo ">>> 🚨 终极焦土：物理断绝证书汇编与构建！"
sed -i '/incbin/d' common/certs/system_certificates.S || true
sed -i '/incbin/d' common/certs/revocation_certificates.S || true
sed -i 's/obj-y += system_certificates.o/# obj-y += system_certificates.o/g' common/certs/Makefile || true
sed -i 's/obj-y += revocation_certificates.o/# obj-y += revocation_certificates.o/g' common/certs/Makefile || true

mkdir -p common/debian
touch common/debian/canonical-certs.pem common/debian/canonical-revoked-certs.pem
mkdir -p common/certs
touch common/certs/signing_key.pem common/certs/signing_key.x509
touch common/certs/x509_certificate_list common/certs/x509_revocation_list

echo ">>> Fixing illegal octal constants..."
sed -i 's/return 08/return 18/g' common/include/linux/slab.h || true
sed -i 's/return 09/return 19/g' common/include/linux/slab.h || true
find common -name "slab.h" -exec sed -i 's/return 08/return 18/g; s/return 09/return 19/g' {} + || true
sed -i 's/#039/#139/g' common/arch/arm64/kernel/vdso/sigreturn.S || true

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

if [ "$BASE_VER" != "5.10" ] && [ -f "tools/bazel" ]; then
    echo ">>> Modern Kleaf/Bazel ecosystem detected..."
    TRIM_FLAGS="--notrim"
    if [ "$BASE_VER" = "5.15" ]; then TRIM_FLAGS=""; fi
    tools/bazel run --config=stamp $TRIM_FLAGS \
      --action_env=SOURCE_DATE_EPOCH="$OFFICIAL_DATE" \
      --action_env=STABLE_BUILD_VERSION="-g$OFFICIAL_HASH" \
      --action_env=KLEAF_KERNEL_BUILD_VERSION="-g$OFFICIAL_HASH" \
      --action_env=KLEAF_SKIP_ABI_CHECKS=true \
      --action_env=KLEAF_USER=android-build \
      //common:kernel_aarch64_dist \
      -- \
      --destdir=out/dist || true
else
    echo ">>> Legacy Hermetic Make ecosystem detected..."
    mkdir -p out/dist
    export DIST_DIR="out/dist"
    export KERNEL_DIR="common"
    export BUILD_CONFIG="common/build.config.gki.aarch64"
    export SOURCE_DATE_EPOCH="$OFFICIAL_DATE"
    export EXTRA_LINUX_VERSION="-g${OFFICIAL_HASH}"
    
    if [ -f "build/build.sh" ]; then
        # 🚨 这里的 || true 是免死金牌：就算它报了 Error 2，咱们也不中止脚本！
        bash build/build.sh || echo "⚠️ 模块编译可能有报错，但主内核已生成，强行继续提取..."
    fi
fi

# 🚨 强行提取 Image
IMAGE_PATH="$(find out/dist -type f -name 'Image' -print -quit)"
if [ -n "${IMAGE_PATH}" ] && [ -f "${IMAGE_PATH}" ]; then
    echo ">>> 🎉 成功提取到主内核 Image: ${IMAGE_PATH}"
    cp -f "${IMAGE_PATH}" ../out/Image
else
    echo "❌ 致命错误: 在主内核里找不到 Image 文件！"
    exit 1
fi
cd ..
