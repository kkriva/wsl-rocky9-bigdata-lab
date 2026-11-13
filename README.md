# WSL2 + Rocky Linux 9 大数据实验环境搭建指南

在 Windows 笔记本上用 WSL2 部署 Rocky Linux 9，作为大数据课程（Hadoop / Spark / Hive）的实验环境。本指南按真实安装过程整理，包含每一步的命令、验证方法和踩坑记录，照着走大约 45–60 分钟。

> 适用场景：Windows 10（2004 / 19041 及以上）或 Windows 11，需要一个与 RHEL 系教材命令一致的 Linux 实验环境。
>
> 验证环境（2026-11-13 实测）：Windows 11 10.0.26100.4770，WSL 3.0.5.0，Rocky Linux 9.8 (Blue Onyx)，systemd 252，OpenJDK 11.0.25，主机名 `rocky01`，实验用户 `hadoop`。

## 目录

- [流程总览](#流程总览)
- [1. 前置检查](#1-前置检查)
- [2. 开启 Windows 功能并安装 WSL2](#2-开启-windows-功能并安装-wsl2)
- [3. 导入 Rocky Linux 9](#3-导入-rocky-linux-9)
- [4. 换源与初始化](#4-换源与初始化)
- [5. 环境自检](#5-环境自检)
- [6. 日常启动、退出与备份](#6-日常启动退出与备份)
- [故障速查表](#故障速查表)
- [仓库内容](#仓库内容)
- [参考链接](#参考链接)

## 流程总览

| 步骤 | 内容 | 预计时间 |
| --- | --- | --- |
| 1 | 前置检查：系统版本、CPU 虚拟化、C 盘空间 | 约 5 分钟 |
| 2 | 开启两个 Windows 功能，安装 WSL2 并确认版本 | 约 10 分钟（含一次重启） |
| 3 | 下载官方 `.wsl` 镜像导入 Rocky Linux 9，建用户、写 `wsl.conf` | 约 10–20 分钟（看网速） |
| 4 | 换国内源、更新系统、建目录、配 hosts、SSH 免密、装 JDK | 约 20 分钟 |
| 5 | 跑 6 项自检，全部通过后立刻备份 | 约 5 分钟 |

约定：

- 标有 **PowerShell** 的命令在 Windows 的 PowerShell / Windows 终端里执行；安装阶段需要**管理员**权限，日常使用普通权限即可。
- 标有 **Rocky** 的命令在 Rocky Linux 的 Bash 里执行，提示符形如 `[hadoop@rocky01 ~]$`。
- 所有路径建议使用纯英文、无空格目录，例如 `D:\wsl\`、`D:\backup\`。

## 1. 前置检查

三项缺一不可，先查再动手。

1. **系统版本**：按 `Win + R`，输入 `winver` 回车。需要 Windows 10 版本 2004 及以上（内部版本 19041 及以上），或 Windows 11。
2. **CPU 虚拟化已开启**：打开任务管理器 → 性能 → CPU，右下角看“虚拟化”是否为“已启用”。若显示“已禁用”，重启进 BIOS 打开 Intel VT-x 或 AMD-V。
3. **C 盘至少留出 20GB**：设置 → 系统 → 存储，查看 C 盘可用空间。WSL 虚拟磁盘默认放在 C 盘，会随使用增长；Rocky 镜像本身只有约 140 MB。

## 2. 开启 Windows 功能并安装 WSL2

### 2.1 开启两个功能（PowerShell，管理员）

两项要一起开，缺一项 WSL2 就跑不起来。执行完需要重启电脑。

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

图形界面等价做法：`Win + R` 输入 `optionalfeatures` 回车，勾选“适用于 Linux 的 Windows 子系统”和“虚拟机平台”，点“确定”后重启。

### 2.2 安装 WSL（PowerShell，管理员）

```powershell
wsl --install
wsl --version
wsl --update
wsl -l -v
```

说明：

- `wsl --install` 会自动开启所需功能、下载 WSL 内核，并安装默认发行版 Ubuntu。先留着它，不影响后面装 Rocky Linux。
- `wsl --version` 需不低于 `0.67.6`，否则后面启用不了 systemd。本指南实测为 `3.0.5.0`。
- `wsl -l -v` 若提示“没有已安装的分发”，不是报错，说明 WSL 本体已装好但还没装任何 Linux，正好干净地装 Rocky。

### 2.3 下载失败时的备用通道

`wsl --install` / `wsl --update` 在部分网络（尤其是校园网）下可能报 `已禁止 (403)`，或下载到一半超时。WSL 的下载不支持断点续传，断了只能从头来。按以下顺序排查，不要在同一个网络下反复跑同一条命令：

1. 关掉 VPN、代理、WARP、游戏加速器一类工具，改连手机热点换一个出口 IP 再试。共享出口 IP 触发限流时也表现为 403。
2. 只装本体、不装发行版，减少下载量（后面本来就要导入 Rocky，不需要 Ubuntu）：

   ```powershell
   wsl --install --no-distribution
   ```

3. 改走 GitHub 下载通道，不走 Microsoft Store：

   ```powershell
   wsl --update --web-download
   ```

4. 最稳的办法是浏览器手动下载：在 [WSL 官方 Releases](https://github.com/microsoft/WSL/releases/latest) 页找到标着 Latest 的版本，下载 x64 的 `.msi` 安装包，双击安装，重启电脑后再跑 `wsl --version` 验证。不要下 ARM64 的，也不要下 Source code 压缩包。手动装 MSI 之前要先确认 2.1 的两个功能已开启并重启过，否则 MSI 可能报错。

## 3. 导入 Rocky Linux 9

本指南统一走官方 `.wsl` 镜像路线（路线 A）。另一条容器 rootfs + `wsl --import` 路线需要手动建用户、手动开 systemd、还要先把 `.tar.xz` 解成 `.tar`，只在官方镜像实在下不动时考虑。

### 3.1 下载镜像

下载目录：<https://dl.rockylinux.org/pub/rocky/9/images/x86_64/>

文件名：`Rocky-9-WSL-Base.latest.x86_64.wsl`（约 140 MB，本指南实测对应 Rocky 9.8 构建）。下载慢的话可以在目录页换一个离你更近的镜像站。

把文件放到纯英文、无空格的目录，例如 `D:\wsl\`。路径带中文或空格时 `--from-file` 很容易报错。

### 3.2 导入（PowerShell，管理员）

```powershell
wsl --install --from-file D:\wsl\Rocky-9-WSL-Base.latest.x86_64.wsl --name RockyLinux9
wsl --set-default RockyLinux9
wsl -d RockyLinux9
```

也可以双击 `.wsl` 文件安装，但命令行导入可以自己指定发行版名字，推荐用命令行。

### 3.3 首次启动建用户

首次进入时会提示 `Enter new UNIX username:`，输入实验用户名：

```text
hadoop
```

注意不同镜像版本的行为可能不同：

- 有的版本会接着让你输两次密码，输密码时屏幕上什么都不显示，输完回车就行。
- 本指南实测的 Rocky 9.8 镜像建完用户后直接进入系统，并提示该用户已在 `wheel` 组、可用免密 `sudo`，想设密码需自行运行 `sudo passwd hadoop`。如果出现这种情况，不要把密码当成命令直接敲（会被当成命令执行并报 `command not found`），而是先跑 `sudo passwd hadoop`，再在提示下输两次新密码。密码自己记好，不要截图外泄，也不要在不同地方重复使用已经外泄过的密码。

首次启动还可能出现两行可以忽略的提示：localhost 代理警告（NAT 模式不支持 localhost 代理镜像）和 `cloud-init.service` 不存在的提示，都不影响做实验。

进去后先验证系统版本：

```bash
cat /etc/os-release
```

应显示 `Rocky Linux 9.8 (Blue Onyx)` 左右的版本信息。注意路径是 `/etc/os-release`，不要打成 `/ect/os-release`。

### 3.4 写 wsl.conf，启用 systemd（Rocky）

这是最容易跳过、也最容易栽跟头的一步。不开 systemd，`systemctl` 会直接报错，`sshd` 和后续服务化启动全部失败。

整段一起复制粘贴（见[粘贴注意事项](#粘贴注意事项)）：

```bash
sudo tee /etc/wsl.conf > /dev/null <<'EOF'
[boot]
systemd=true
[user]
default=hadoop
[network]
hostname=rocky01
generateHosts=true
EOF
cat /etc/wsl.conf
```

`cat` 出来的内容应与上面 7 行一模一样。完整内容另见 [`examples/wsl.conf`](examples/wsl.conf)。

写完必须彻底重启 WSL，光关终端窗口不算。先退出 Rocky，再到 PowerShell 里执行（注意：先 `exit`、等回到 `PS` 提示符，再粘贴后面的 PowerShell 命令，不要把 `exit` 和 PowerShell 命令一起粘进 Rocky 里，否则后面的命令可能在切换 shell 时被吞掉而不执行）：

```powershell
exit
wsl --shutdown
wsl --set-default RockyLinux9
wsl -d RockyLinux9
```

重新进去后提示符应变成 `hadoop@rocky01` 开头。验证：

```bash
hostname
systemctl --version | head -1
```

应分别显示 `rocky01` 和 `systemd 252 ...` 左右的版本号。

> 如果 `hostname` 报 `command not found`，不是主机名没改好，而是这个精简镜像里本来就没装 `hostname` 工具。先用 `uname -n` 验证（应显示 `rocky01`），后面装基础软件时把 `hostname` 一起装上即可。

## 4. 换源与初始化

### 4.1 换阿里云源（Rocky）

默认 Rocky 源在国外，dnf 下载很慢或超时。先备份原配置再替换，整段粘贴：

```bash
sudo cp -r /etc/yum.repos.d /etc/yum.repos.d.bak
sudo sed -e 's|^mirrorlist=|#mirrorlist=|g' -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.aliyun.com/rockylinux|g' -i.bak /etc/yum.repos.d/*.repo
sudo dnf clean all && sudo dnf makecache
```

成功标志：BaseOS 和 AppStream 都跑出几十 MB 的下载速度，最后显示 `Metadata cache created`。

### 4.2 更新系统并启用附加仓库（Rocky）

```bash
sudo dnf -y update
sudo dnf config-manager --set-enabled crb
sudo dnf install -y epel-release
```

说明：

- `dnf -y update` 会把所有包升到最新，耗时取决于网速和包数量，耐心等到提示符回来。
- 如果 `config-manager` 报 `command not found`，先装插件包再重试：`sudo dnf install -y dnf-plugins-core`。
- CRB（CodeReady Builder）和 EPEL 提供一些实验常用的附加包，顺手启用，后面用到时不会再卡。

### 4.3 建实验目录（Rocky）

```bash
sudo mkdir -p /opt/module /opt/software
sudo chown -R hadoop:hadoop /opt/module /opt/software
```

约定：`/opt/module` 放 Hadoop、JDK、Spark 这类解压后的程序，`/opt/software` 放下载的压缩包。`chown` 让 hadoop 用户有写权限，后续不用每次都 `sudo`。

### 4.4 装基础软件（Rocky）

```bash
sudo dnf install -y openssh-server openssh-clients rsync wget vim net-tools hostname
```

`hostname` 不在教材默认列表里，但这个镜像没自带它，装上后 `hostname` 命令才能用。

### 4.5 主机名解析（Rocky）

因为 `wsl.conf` 里设了 `generateHosts=true`，WSL 会自动生成 `/etc/hosts`。查看一下：

```bash
cat /etc/hosts
```

典型内容里会有一行：

```text
127.0.1.1 rocky01.localdomain rocky01
```

不要因为它不是 `127.0.0.1` 就再手加一行。`127.0.0.1` 和 `127.0.1.1` 都在本地回环网段里，ping 和 Hadoop 都能正常用；而且自动生成的这行重启后还在，手加的 `127.0.0.1 rocky01` 反而可能被 WSL 重启后覆盖掉（这是 `generateHosts=true` 的本意）。只在自动生成的 `/etc/hosts` 里完全没有 `rocky01` 时才需要手动处理，那时应先把 `generateHosts` 改成 `false` 再手动写文件并重启 WSL。

验证：

```bash
ping -c 2 rocky01
```

应显示 2 个包全部收到、`0% packet loss`，解析地址为 `127.0.1.1`。

### 4.6 SSH 免密登录（Rocky）

Hadoop 伪分布式需要节点之间互相免密登录，本机也要能免密登录本机。分两步：先启动服务并生成密钥，再把公钥放进授权文件。交互步骤要单独执行（见[粘贴注意事项](#粘贴注意事项)）：

```bash
sudo systemctl enable --now sshd
ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

然后单独执行：

```bash
ssh localhost
```

第一次连接会提示确认主机指纹，输入完整的 `yes` 回车。之后应直接进入新的 shell、没有任何密码提示，提示符仍是 `hadoop@rocky01`。输 `exit` 退回即可。

> 如果 `ssh localhost` 仍然要密码，先检查三点：`systemctl status sshd` 是否在运行；`~/.ssh/authorized_keys` 的权限是否为 `600`；`~/.ssh` 目录权限是否为 `700`。密钥文件不要截图外泄。

### 4.7 安装 JDK 11 并配置 JAVA_HOME（Rocky）

Hadoop 对 Java 版本很敏感，实验统一用 JDK 11，不要装 JDK 8 或 17。

```bash
sudo dnf install -y java-11-openjdk-devel
java -version
ls /usr/lib/jvm/
```

`java -version` 应显示 `openjdk version "11.0.x"`。`ls /usr/lib/jvm/` 里会同时出现 `java-11-openjdk`、`java-11-openjdk-11.0.x...`（带版本号的真实目录）、`jre` 等条目。

配置环境变量时要当心一个常见坑：教材里手工解压 JDK 的示例用的是 `JAVA_HOME=/opt/module/jdk-11`，那条路径只对“手动下载 tarball 解压到 `/opt/module`”的路线成立。走 dnf 安装时，JAVA_HOME 必须指向 `/usr/lib/jvm/` 下的目录，且应选稳定的软链接 `java-11-openjdk`，不要选带版本号的目录（下次更新 JDK 后目录名会变），也不要选 `jre` 开头的条目（那是运行时，没有 `javac`）。

```bash
sudo tee /etc/profile.d/my_env.sh > /dev/null <<'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH=$JAVA_HOME/bin:$PATH
EOF
cat /etc/profile.d/my_env.sh
source /etc/profile.d/my_env.sh && echo $JAVA_HOME && ls $JAVA_HOME/bin/javac
```

应显示 `/usr/lib/jvm/java-11-openjdk`，且 `javac` 存在。完整内容另见 [`examples/my_env.sh`](examples/my_env.sh)。

> 如果你只是在命令行里敲了 `/usr/lib/jvm/java-11-openjdk` 这一串路径回车，会报 `Is a directory`。这不是配置失败，路径本身不是命令，不用管。
>
> 换个新窗口再跑 `echo $JAVA_HOME`，应仍显示同一路径，说明 `/etc/profile.d` 正常加载。如果新窗口里为空，说明你的 shell 没加载 `/etc/profile.d`，需要把上面两行 `export` 再追加进 `~/.bashrc`。

## 5. 环境自检

用脚本一次验证 6 项，6 项都必须有输出、不能空白或报错。脚本见 [`scripts/check-env.sh`](scripts/check-env.sh)，内容如下：

```bash
#!/bin/bash
grep PRETTY_NAME /etc/os-release
uname -r
systemctl --version | head -1
hostname
ssh -o BatchMode=yes localhost echo OK
java -version 2>&1 | head -1
```

生成并运行（建议用 `printf` 单行生成，避免多行 heredoc 粘贴时被终端转义符号打断，见[粘贴注意事项](#粘贴注意事项)）：

```bash
printf '%s\n' '#!/bin/bash' 'grep PRETTY_NAME /etc/os-release' 'uname -r' 'systemctl --version | head -1' 'hostname' 'ssh -o BatchMode=yes localhost echo OK' 'java -version 2>&1 | head -1' > ~/check-env.sh
cat ~/check-env.sh
chmod +x ~/check-env.sh && ~/check-env.sh
```

预期输出示例（版本号随镜像和更新略有不同，关键是 6 行齐全、SSH 那行是 `OK`）：

```text
PRETTY_NAME="Rocky Linux 9.8 (Blue Onyx)"
6.18.58.1-1-microsoft-standard-WSL2
systemd 252 (252-67.el9.rocky.0.1)
rocky01
OK
openjdk version "11.0.25" 2024-10-15 LTS
```

如果某一行空白或报错，按顺序往回查：先查 Windows 功能和虚拟化（第 2 步），再查 systemd 和 `wsl.conf`（第 3.4 步），最后查网络源和对应软件包（第 4 步）。

## 6. 日常启动、退出与备份

### 6.1 日常启动（PowerShell，普通权限即可）

因为 RockyLinux9 已设为默认发行版，打开 PowerShell 或 Windows 终端，输：

```powershell
wsl
```

推荐加 `~`，一进去就在家目录，不会落在 `system32` 里：

```powershell
wsl ~
```

想写明确一点也可以用：

```powershell
wsl -d RockyLinux9
```

Windows 终端里也可以点顶部的下拉箭头，直接选 RockyLinux9 开一个新标签页。关机或 `wsl --shutdown` 后的第一次启动要等几秒（systemd 启动），等提示符出现再操作。

### 6.2 退出与彻底停止

日常用完输 `exit` 退出就行，不用每次都彻底停止。只有改了 `wsl.conf` 才需要到 PowerShell 里彻底重启：

```powershell
wsl --shutdown
```

查看状态：

```powershell
wsl -l -v
```

`Running` 表示在跑，`Stopped` 表示已停，下次进入会自动再起来。名字前带 `*` 的是默认发行版。

### 6.3 备份（PowerShell）

环境跑通后**立刻**备份一份，以后实验把系统搞崩了，几分钟就能还原，不用从头重装。一条一条执行，等提示符回来再执行下一条：

```powershell
New-Item -ItemType Directory -Force -Path D:\backup
wsl --shutdown
wsl --export RockyLinux9 D:\backup\rocky9-backup.tar
Get-Item D:\backup\rocky9-backup.tar
```

`wsl --export` 需要一两分钟，期间不要关窗口。成功后显示“操作成功完成”，`Get-Item` 能看到一个 1 GB 多的 `.tar` 文件（本指南实测约 1364 MB）。备份文件不要删，也不要改名。

### 6.4 还原（PowerShell，仅在系统搞崩时用）

还原前要先注销掉已损坏的同名发行版（这一步会删掉当前这个发行版的所有数据，确认备份文件存在且无误再执行），然后再导入：

```powershell
wsl --unregister RockyLinux9
New-Item -ItemType Directory -Force -Path D:\wsl\RockyLinux9
wsl --import RockyLinux9 D:\wsl\RockyLinux9 D:\backup\rocky9-backup.tar --version 2
wsl -d RockyLinux9
```

还原后重新跑一遍第 5 节的自检，确认 6 项都通过。

## 故障速查表

| 现象 | 原因 | 做法 |
| --- | --- | --- |
| `wsl --install` 报 `已禁止 (403)` 或下载超时 | 校园网共享 IP 被限流，或 VPN / 代理干扰；下载不支持断点续传 | 关 VPN / 代理，换手机热点；或 `--install --no-distribution`；或 `--update --web-download`；或手动下 MSI（见 2.3） |
| 导入时报 `无法检测到虚拟化支持` / `HCS_E_SERVICE_NOT_AVAILABLE` / `0x80370102` | 两个 Windows 功能没开，或 BIOS 里虚拟化没开 | 按 2.1 开两项功能并**重启电脑**（不是关机），再查任务管理器里虚拟化是否为“已启用”，然后重新导入 |
| `wsl --version` 提示必须更新，出现 60 秒倒计时 |  inbox WSL 版本太旧 | 按 Ctrl-C 取消倒计时，按 2.3 的备用通道更新，不要在倒计时里按任意键重试同一条失败下载 |
| 首次启动出现 localhost 代理警告或 `cloud-init.service` 提示 | NAT 模式不支持代理镜像；镜像里没有 cloud-init 服务 | 忽略，不影响实验 |
| `hostname: command not found` | 精简镜像没装 `hostname` 工具 | 用 `uname -n` 验证主机名；装基础软件时加上 `hostname`（见 4.4） |
| `sudo passwd hadoop` 之前把密码当命令敲了，报 `command not found` | 该镜像建用户后不立即要求设密码，提示符已是正常 shell | 先跑 `sudo passwd hadoop` 再输密码；已当成命令敲出去的字符串不要再用作密码 |
| `cat /etc/hosts` 里是 `127.0.1.1 rocky01` 不是 `127.0.0.1` | WSL 自动生成，`generateHosts=true` 的正常行为 | 留着别动，ping 和 Hadoop 都能用；不要手加 `127.0.0.1` 那行（见 4.5） |
| `ssh localhost` 要密码 | sshd 没跑、密钥没放好、或权限不对 | 查 `systemctl status sshd`，确认 `authorized_keys` 为 `600`、`~/.ssh` 为 `700`（见 4.6） |
| `JAVA_HOME` 指向 `/opt/module/jdk-11` 后 `javac` 找不到 | dnf 安装的 JDK 不在那个路径 | 改成 `/usr/lib/jvm/java-11-openjdk`（见 4.7） |
| 敲 JDK 路径回车报 `Is a directory` | 路径不是命令 | 不用管，路径只是用来赋值给 `JAVA_HOME` 的 |
| 粘贴命令时出现 `[[200`、`^[[200~` 乱码，或 heredoc 卡在 `>` 提示符 | 终端粘贴转义（bracketed paste）把多行内容打乱，`EOF` 没被识别 | 按 Ctrl-C 退回提示符，改成单行命令或一次只粘一行；交互行（输密码、`yes`、`ssh localhost`）必须单独执行；`check-env.sh` 用 `printf` 单行生成（见第 5 节） |
| 把 `exit` 和 PowerShell 命令一起粘贴后，备份命令没执行 | 切换 shell 时后面的输入被吞掉 | 先 `exit`、等回到 `PS` 提示符，再一条一条粘贴 PowerShell 命令（见 3.4、6.3） |
| `dnf` 很慢或超时 | 还没换国内源 | 按 4.1 换阿里云源并 `makecache` 后再试 |
| `config-manager` 报 `command not found` | 没装插件包 | 先 `sudo dnf install -y dnf-plugins-core`，再启用 CRB（见 4.2） |

### 粘贴注意事项

终端反复出现粘贴乱码时，记住三条：

1. 非交互命令块可以整段粘贴，交互步骤（输密码、输 `yes`、第一次 `ssh`）必须单独执行。
2. 出现 `>` 续行提示符且退不出来时，按 Ctrl-C 回到正常提示符再重来，不用重启窗口；重启窗口也是安全的，已经写进文件的配置不会丢。
3. 粘贴后先看一眼回显，确认没有 `[[200`、`^[[200~` 这类符号再回车，出现乱码就 Ctrl-C 重打。

## 仓库内容

```text
README.md              本指南
scripts/check-env.sh   6 项环境自检脚本（第 5 节）
examples/wsl.conf      /etc/wsl.conf 参考内容（第 3.4 节）
examples/my_env.sh     /etc/profile.d/my_env.sh 参考内容，dnf 路线的 JAVA_HOME（第 4.7 节）
```

使用时把 `examples/` 里的文件内容复制到对应路径即可，不要直接把整个 `examples` 目录拷进系统目录。

## 参考链接

- WSL 官方安装文档：<https://learn.microsoft.com/windows/wsl/install>
- Rocky Linux 官方 WSL 导入指南：<https://docs.rockylinux.org/guides/interoperability/import_rocky_to_wsl/>
- WSL 官方 Releases（手动下载 `.msi`）：<https://github.com/microsoft/WSL/releases/latest>
- Rocky Linux 9 镜像目录（`.wsl` 镜像）：<https://dl.rockylinux.org/pub/rocky/9/images/x86_64/>

## 声明

本指南是学习笔记，按一次真实安装过程整理，不含课程课件原文。命令和版本号以你自己的环境为准，遇到与教材不一致的地方，以教材要求和老师说明为准。密码、密钥、个人学号姓名不要放进公开仓库或截图里。
