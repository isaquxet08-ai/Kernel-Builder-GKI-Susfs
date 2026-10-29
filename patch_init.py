import os
import re
import sys

# AOSP 源码的根目录（在 Actions 里我们会把它放在当前目录的 aosp 文件夹）
AOSP_DIR = "aosp"

def patch_file(filepath):
    full_path = os.path.join(AOSP_DIR, filepath)
    if not os.path.exists(full_path):
        print(f"⚠️ 找不到文件: {full_path}")
        return
        
    with open(full_path, 'r') as f:
        content = f.read()

    # 1. 把所有致命错误降级
    content = content.replace('LOG(FATAL)', 'LOG(WARNING)')
    content = content.replace('PLOG(FATAL)', 'PLOG(WARNING)')
    
    # 2. 暴力解除 abort 和 直接返回
    content = content.replace('abort();', '/* abort disabled by geek */')
    content = content.replace('return false;', 'return true; /* ignored by geek */')
    
    # 3. 宽容挂载失败 (捕捉 EBUSY 和 ENOENT)
    pattern = r'if\s*\(\s*(mount\s*\([^;]+?\))\s*!=\s*0\s*\)'
    replacement = r'if (\1 != 0 && errno != EBUSY && errno != ENOENT)'
    content = re.sub(pattern, replacement, content)

    # 4. 强行无视 sysfs 挂载失败
    content = re.sub(r'if\s*\(\s*mount\(\s*"sysfs",\s*"/sys".*?\)\s*<\s*0\s*\)', 
                     'if (false) /* ignore sysfs mount error */', content)

    with open(full_path, 'w') as f:
        f.write(content)
    print(f"✅ 已修补: {filepath}")

if __name__ == "__main__":
    print(">>> 开始对 init 源码打补丁...")
    patch_file('system/core/init/first_stage_init.cpp')
    patch_file('system/core/init/first_stage_mount.cpp')
    patch_file('system/core/init/init.cpp')
    print(">>> 补丁全部注入成功！")
