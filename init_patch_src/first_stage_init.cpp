// 魔改版 first_stage_init.cpp
#include <android-base/logging.h>
#include <sys/mount.h>
#include <errno.h>

// 核心逻辑：宽容一切挂载
bool DoFirstStageMount() {
    // 尝试挂载 sysfs
    if (mount("sysfs", "/sys", "sysfs", 0, NULL) != 0) {
        if (errno == EBUSY) {
            LOG(WARNING) << "sysfs already mounted, ignoring...";
        } else {
            LOG(WARNING) << "sysfs mount failed, ignoring...";
        }
    }
    
    // 尝试挂载 selinuxfs
    if (mount("selinuxfs", "/sys/fs/selinux", "selinuxfs", 0, NULL) != 0) {
        if (errno == EBUSY) {
            LOG(WARNING) << "selinuxfs already mounted, ignoring...";
        }
    }
    
    return true; // 永远返回成功！
}
