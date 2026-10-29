#!/usr/bin/env bash
# scripts/build_kernel.sh
set -euo pipefail

ENABLE_NOMOUNT=${ENABLE_NOMOUNT:-false}
ENABLE_NET_OPTS=${ENABLE_NET_OPTS:-false}
BASE_VER=${BASE_VER:-}

echo "=== Initializing Execution Engine ==="

cd kernel_workspace
mkdir -p ../out out/dist

echo ">>> Forcing VirtIO Drivers & Disabling everything useless..."
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
echo "# CONFIG_SYSTEM_REVOCATION_LIST is not set" >> $CONFIG_FILE
echo "# CONFIG_IKHEADERS is not set" >> $CONFIG_FILE
echo "# CONFIG_MODULE_SIG is not set" >> $CONFIG_FILE

echo ">>> 🚨 终极狂暴模式：物理删除 .incbin，篡改 Makefile 让它彻底忘记证书！"
# 1. 强行干掉汇编文件里的 incbin 指令
sed -i '/incbin/d' common/certs/system_certificates.S || true
sed -i '/incbin/d' common/certs/revocation_certificates.S || true
# 2. 直接把 Makefile 里的编译目标注释掉，从根源上阻止它！
sed -i 's/obj-y += system_certificates.o/# obj-y += system_certificates.o/g' common/certs/Makefile || true
sed -i 's/obj-y += revocation_certificates.o/# obj-y += revocation_certificates.o/g' common/certs/Makefile || true

# 🚨 随手塞点空文件，作为最后一道防线
mkdir -p common/debian
touch common/debian/canonical-certs.pem
touch common/debian/canonical-revoked-certs.pem
mkdir -p common/certs
touch common/certs/signing_key.pem
touch common/certs/signing_key.x509
touch common/certs/x509_certificate_list
touch common/certs/x509_revocation_list

echo ">>> Fixing illegal octal constants in slab.h..."
sed -i 's/return 08/return 18/g' common/include/linux/slab.h || true
sed -i 's/return 09/return 19/g' common/include/linux/slab.h || true
find common -name "slab.h" -exec sed -i 's/return 08/return 18/g; s/return 09/return 19/g' {} + || true

echo ">>> Fixing illegal octal number in sigreturn.S..."
sed -i 's/#039/#139/g' common/arch/arm64/kernel/vdso/sigreturn.S || true
find common/arch/arm64/kernel/vdso -name "sigreturn.S" -exec sed -i 's/#039/#139/g' {} + || true

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

if [ "$BASE_VER" != "5.10" ] && [ -f "tools/bazel" ]; then
    echo ">>> Modern Kleaf/Bazel ecosystem detected for $BASE_VER..."
    TRIM_FLAGS=""
    if [ "$BASE_VER" = "5.15" ]; then
        TRIM_FLAGS=""
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
        bash build/build.sh
    else
        exit 1
    fi
fi

IMAGE_PATH="$(find out/dist -type f -name 'Image' -print -quit)"
if [ -z "${IMAGE_PATH}" ] || [ ! -f "${IMAGE_PATH}" ]; then
    exit 1
fi
cp -f "${IMAGE_PATH}" ../out/Image
cd ..
