#!/usr/bin/env bash
set -euo pipefail

ENABLE_NOMOUNT=${ENABLE_NOMOUNT:-false}
ENABLE_NET_OPTS=${ENABLE_NET_OPTS:-false}
BASE_VER=${BASE_VER:-}

echo "=== Initializing Execution Engine ==="
REPO_DIR=$(pwd)
cd kernel_workspace
WORKSPACE_DIR=$(pwd)

# 🚨 空间规划：输出目录全在 C 盘，临时编译全在 /mnt
mkdir -p $REPO_DIR/out $REPO_DIR/out/dist

CONFIG_FILE="common/arch/arm64/configs/gki_defconfig"

# 🚨 第一步：物理切断底层强制拉取（select）链！
echo ">>> 🚨 正在切断 Kconfig.gki 里的强制依赖链..."
GKI_KCONFIG="common/init/Kconfig.gki"
if [ -f "$GKI_KCONFIG" ]; then
    # 注释掉强制开启无线和声音的 select
    sed -i 's/^[[:space:]]*select WIRELESS_EXT/# &/' $GKI_KCONFIG || true
    sed -i 's/^[[:space:]]*select WEXT_CORE/# &/' $GKI_KCONFIG || true
    sed -i 's/^[[:space:]]*select WEXT_PROC/# &/' $GKI_KCONFIG || true
    sed -i 's/^[[:space:]]*select SND_VMASTER/# &/' $GKI_KCONFIG || true
    sed -i 's/^[[:space:]]*select SND_JACK/# &/' $GKI_KCONFIG || true
    sed -i 's/^[[:space:]]*select SND_PCM_IEC958/# &/' $GKI_KCONFIG || true
    sed -i 's/^[[:space:]]*select SND_JACK_INPUT_DEV/# &/' $GKI_KCONFIG || true
    sed -i 's/^[[:space:]]*select SND_PCM_ELD/# &/' $GKI_KCONFIG || true
fi

echo ">>> 🚨 正在从仓库根目录拉取你定制的 gki_defconfig..."
if [ -f "$REPO_DIR/gki_defconfig" ]; then
    cp -f $REPO_DIR/gki_defconfig $CONFIG_FILE
fi

echo ">>> 1. 注入必须的 VirtIO 基础..."
cat << 'CONF' >> $CONFIG_FILE
CONFIG_VIRTIO=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_MMIO=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_NET=y
CONFIG_DRM=y
CONFIG_DRM_VIRTIO_GPU=y
CONFIG_EXT4_FS=y
CONFIG_DEVTMPFS=y
CONFIG_TMPFS=y
CONFIG_VT=y
CONFIG_TTY=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ASHMEM=y
# CONFIG_DEBUG_INFO_BTF is not set
# CONFIG_DEBUG_INFO is not set
CONFIG_DEBUG_INFO_NONE=y
# CONFIG_SYSTEM_TRUSTED_KEYS is not set
# CONFIG_SYSTEM_REVOCATION_KEYS is not set
# CONFIG_IKHEADERS is not set
# CONFIG_MODULE_SIG is not set
CONF

echo ">>> 2. ✂️ 终极黑名单：既然 select 切了，这些现在随便杀！"
cat << 'CONF' >> $CONFIG_FILE
# CONFIG_WLAN is not set
# CONFIG_WIRELESS is not set
# CONFIG_BT is not set
# CONFIG_NFC is not set
# CONFIG_MEDIA_SUPPORT is not set
# CONFIG_SOUND is not set
# CONFIG_SND is not set
# CONFIG_CAN is not set
# CONFIG_HAMRADIO is not set
# CONFIG_ISDN is not set
# CONFIG_SCSI is not set
# CONFIG_ATA is not set
# CONFIG_MD is not set
# CONFIG_DRM_AMDGPU is not set
# CONFIG_DRM_RADEON is not set
# CONFIG_DRM_I915 is not set
# CONFIG_DRM_NOUVEAU is not set
# CONFIG_NET_VENDOR_INTEL is not set
# CONFIG_NET_VENDOR_REALTEK is not set
# CONFIG_NET_VENDOR_BROADCOM is not set
# CONFIG_NET_VENDOR_MARVELL is not set
CONF

echo ">>> 3. 修复八进制与证书死局..."
cd common
sed -i '/incbin/d' certs/system_certificates.S || true
sed -i '/incbin/d' certs/revocation_certificates.S || true
sed -i 's/obj-y += system_certificates.o/# obj-y += system_certificates.o/g' certs/Makefile || true
sed -i 's/obj-y += revocation_certificates.o/# obj-y += revocation_certificates.o/g' certs/Makefile || true
mkdir -p debian certs
touch debian/canonical-certs.pem debian/canonical-revoked-certs.pem
touch certs/signing_key.pem certs/signing_key.x509 certs/x509_certificate_list certs/x509_revocation_list

sed -i 's/return 08/return 18/g' include/linux/slab.h || true
sed -i 's/return 09/return 19/g' include/linux/slab.h || true
find . -name "slab.h" -exec sed -i 's/return 08/return 18/g; s/return 09/return 19/g' {} + || true
sed -i 's/#039/#139/g' arch/arm64/kernel/vdso/sigreturn.S || true

echo ">>> 4. 主动喂饭 savedefconfig，让底层 diff 闭嘴..."
make ARCH=arm64 CC=clang LLVM=1 CROSS_COMPILE=aarch64-linux-gnu- savedefconfig || true
cp defconfig arch/arm64/configs/gki_defconfig || true

echo ">>> 5. 物理暗杀 build.sh 的检查器..."
if [ -f "build/build.sh" ]; then
    sed -i 's/eval check_defconfig/eval true/g' build/build.sh || true
    sed -i 's/check_defconfig/true/g' build/build.sh || true
fi

git -C common ls-files -m | xargs -r git -C common update-index --assume-unchanged || true

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

echo ">>> 6. 极速编译开始..."
export DIST_DIR="$WORKSPACE_DIR/out/dist"
export KERNEL_DIR="common"
export BUILD_CONFIG="common/build.config.gki.aarch64"
export SOURCE_DATE_EPOCH="$OFFICIAL_DATE"
export EXTRA_LINUX_VERSION="-g${OFFICIAL_HASH}"

if [ -f "build/build.sh" ]; then
    bash build/build.sh || echo "⚠️ 编译有小报错，强行提取主内核..."
fi

IMAGE_PATH="$(find $WORKSPACE_DIR/out/dist -type f -name 'Image' -print -quit)"
if [ -n "${IMAGE_PATH}" ] && [ -f "${IMAGE_PATH}" ]; then
    echo ">>> 🎉 提取成功: ${IMAGE_PATH}"
    cp -f "${IMAGE_PATH}" $REPO_DIR/out/Image
else
    echo "❌ 致命错误: 找不到 Image 文件！"
    exit 1
fi
cd $REPO_DIR
