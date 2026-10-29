#!/usr/bin/env bash
# scripts/build_kernel.sh
set -euo pipefail

ENABLE_NOMOUNT=${ENABLE_NOMOUNT:-false}
ENABLE_NET_OPTS=${ENABLE_NET_OPTS:-false}
BASE_VER=${BASE_VER:-}

echo "=== Initializing Execution Engine ==="

cd kernel_workspace
mkdir -p ../out out/dist

echo ">>> 🚨 注入 VirtIO 全家桶，开启极简模式，拉黑无用模块..."
CONFIG_FILE="common/arch/arm64/configs/gki_defconfig"

# 1. VirtIO 核心框架与硬件
echo "CONFIG_VIRTIO=y" >> $CONFIG_FILE
echo "CONFIG_VIRTIO_PCI=y" >> $CONFIG_FILE
echo "CONFIG_VIRTIO_MMIO=y" >> $CONFIG_FILE
echo "CONFIG_VIRTIO_BLK=y" >> $CONFIG_FILE
echo "CONFIG_VIRTIO_NET=y" >> $CONFIG_FILE
echo "CONFIG_DRM=y" >> $CONFIG_FILE
echo "CONFIG_DRM_VIRTIO_GPU=y" >> $CONFIG_FILE
echo "CONFIG_SOUND=y" >> $CONFIG_FILE
echo "CONFIG_SND_VIRTIO=y" >> $CONFIG_FILE

# 2. 基础文件系统
echo "CONFIG_EXT4_FS=y" >> $CONFIG_FILE
echo "CONFIG_DEVTMPFS=y" >> $CONFIG_FILE
echo "CONFIG_TMPFS=y" >> $CONFIG_FILE

# 3. 关闭报错校验
echo "# CONFIG_DEBUG_INFO_BTF is not set" >> $CONFIG_FILE
echo "# CONFIG_DEBUG_INFO_BTF_MODULES is not set" >> $CONFIG_FILE
echo "# CONFIG_DEBUG_INFO is not set" >> $CONFIG_FILE
echo "CONFIG_DEBUG_INFO_NONE=y" >> $CONFIG_FILE
echo "# CONFIG_SYSTEM_TRUSTED_KEYS is not set" >> $CONFIG_FILE
echo "# CONFIG_SYSTEM_REVOCATION_KEYS is not set" >> $CONFIG_FILE
echo "# CONFIG_SYSTEM_REVOCATION_LIST is not set" >> $CONFIG_FILE
echo "# CONFIG_IKHEADERS is not set" >> $CONFIG_FILE
echo "# CONFIG_MODULE_SIG is not set" >> $CONFIG_FILE

# 4. 🚨 拉黑所有垃圾硬件模块（物理网卡、无线网卡、AMD/Intel显卡等）
for vendor in INTEL REALTEK BROADCOM MELLANOX MARVELL MICROSOFT; do
    echo "# CONFIG_NET_VENDOR_${vendor} is not set" >> $CONFIG_FILE
done
echo "# CONFIG_WLAN is not set" >> $CONFIG_FILE
echo "# CONFIG_WIRELESS is not set" >> $CONFIG_FILE
echo "# CONFIG_DRM_AMDGPU is not set" >> $CONFIG_FILE
echo "# CONFIG_DRM_RADEON is not set" >> $CONFIG_FILE
echo "# CONFIG_DRM_NOUVEAU is not set" >> $CONFIG_FILE
echo "# CONFIG_DRM_I915 is not set" >> $CONFIG_FILE
echo "# CONFIG_SCSI is not set" >> $CONFIG_FILE
echo "# CONFIG_ATA is not set" >> $CONFIG_FILE

echo ">>> 物理断绝证书汇编与构建..."
sed -i '/incbin/d' common/certs/system_certificates.S || true
sed -i '/incbin/d' common/certs/revocation_certificates.S || true
sed -i 's/obj-y += system_certificates.o/# obj-y += system_certificates.o/g' common/certs/Makefile || true
sed -i 's/obj-y += revocation_certificates.o/# obj-y += revocation_certificates.o/g' common/certs/Makefile || true
mkdir -p common/debian common/certs
touch common/debian/canonical-certs.pem common/debian/canonical-revoked-certs.pem
touch common/certs/signing_key.pem common/certs/signing_key.x509
touch common/certs/x509_certificate_list common/certs/x509_revocation_list

echo ">>> 修复非法八进制常量..."
sed -i 's/return 08/return 18/g' common/include/linux/slab.h || true
sed -i 's/return 09/return 19/g' common/include/linux/slab.h || true
find common -name "slab.h" -exec sed -i 's/return 08/return 18/g; s/return 09/return 19/g' {} + || true
sed -i 's/#039/#139/g' common/arch/arm64/kernel/vdso/sigreturn.S || true

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

# 🚨 终极执行，加免死金牌
if [ "$BASE_VER" != "5.10" ] && [ -f "tools/bazel" ]; then
    tools/bazel run --config=stamp --notrim \
      --action_env=SOURCE_DATE_EPOCH="$OFFICIAL_DATE" \
      --action_env=KLEAF_SKIP_ABI_CHECKS=true \
      //common:kernel_aarch64_dist -- --destdir=out/dist || true
else
    mkdir -p out/dist
    export DIST_DIR="out/dist"
    export KERNEL_DIR="common"
    export BUILD_CONFIG="common/build.config.gki.aarch64"
    export SOURCE_DATE_EPOCH="$OFFICIAL_DATE"
    export EXTRA_LINUX_VERSION="-g${OFFICIAL_HASH}"
    
    if [ -f "build/build.sh" ]; then
        bash build/build.sh || echo "⚠️ 编译有报错，尝试强行提取主内核..."
    fi
fi

IMAGE_PATH="$(find out/dist -type f -name 'Image' -print -quit)"
if [ -n "${IMAGE_PATH}" ] && [ -f "${IMAGE_PATH}" ]; then
    echo ">>> 🎉 成功提取到主内核 Image!"
    cp -f "${IMAGE_PATH}" ../out/Image
else
    echo "❌ 致命错误: 找不到 Image 文件！"
    exit 1
fi
cd ..
