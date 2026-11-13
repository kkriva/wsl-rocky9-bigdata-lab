# dnf 安装 JDK 11 时的 JAVA_HOME 配置，保存为 /etc/profile.d/my_env.sh。
# 注意：/opt/module/jdk-11 只对手工解压 tarball 的路线成立，dnf 路线不要用那个路径。
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH=$JAVA_HOME/bin:$PATH
