import subprocess
import sys

dependencies = [
    "build-essential", "libncurses5-dev", "bison", "flex", 
    "libssl-dev", "libelf-dev", "zlib1g-dev", "dwarves", 
    "bc", "rsync", "cpio", "kmod", "pahole"
]

def check_and_install():
    print("========================================")
    print("       正在扫描内核编译依赖...          ")
    print("========================================")
    missing = []
    
    for dep in dependencies:
        ret = subprocess.run(["dpkg-query", "-W", "-f='${Status}'", dep], capture_output=True, text=True)
        if "install ok installed" not in ret.stdout:
            missing.append(dep)
    
    if missing:
        print(f"[-] 发现缺失依赖: {', '.join(missing)}")
        print(">>> 正在自动安装补齐...")
        try:
            subprocess.run(["sudo", "apt-get", "update", "-qq"], check=True)
            subprocess.run(["sudo", "apt-get", "install", "-y"] + missing, check=True)
            print("[+] 依赖安装完毕！")
        except subprocess.CalledProcessError as e:
            print(f"[-] 安装失败: {e}")
            sys.exit(1)
    else:
        print("[+] 所有依赖均已就绪，全速前进！")

if __name__ == "__main__":
    check_and_install()
