#!/bin/bash
# 6 项环境自检：Rocky 版本、WSL 内核、systemd、主机名、SSH 免密、JDK 版本。
# 用法：chmod +x scripts/check-env.sh && ./scripts/check-env.sh
# 6 行都必须有输出，SSH 那行应为 OK。详见 README 第 5 节。
grep PRETTY_NAME /etc/os-release
uname -r
systemctl --version | head -1
hostname
ssh -o BatchMode=yes localhost echo OK
java -version 2>&1 | head -1
