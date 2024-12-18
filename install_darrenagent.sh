#!/bin/bash

# 默认版本
VERSION="0.1"
BASE_URL="https://darrenagent-worker.darren-teng-gg.workers.dev"
SYNC_INTERVAL=15  # 默认同步时间为15秒

# 定义Web API的URL和安全密钥
API_URL="$BASE_URL/agent/update"
SEC_KEY="darrenagent-sec-key"

# 解析命令行参数
while getopts "v:i:" opt; do
  case $opt in
    v) VERSION="$OPTARG"
    ;;
    i) SYNC_INTERVAL="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    exit 1
    ;;
  esac
done

# 检查是否已经安装过服务
if systemctl --user is-active --quiet darrenagent.service; then
  # 获取已安装服务的版本
  INSTALLED_VERSION=$(systemctl --user show -p Description darrenagent.service | cut -d'=' -f2 | awk '{print $NF}')
  if [ "$(printf '%s\n' "$VERSION" "$INSTALLED_VERSION" | sort -V | head -n1)" != "$VERSION" ]; then
    echo "当前安装的版本($INSTALLED_VERSION)低于新版本($VERSION)，卸载旧版本..."
    systemctl --user stop darrenagent.service
    systemctl --user disable darrenagent.service
    rm ~/.config/systemd/user/darrenagent.service
  else
    echo "当前安装的版本($INSTALLED_VERSION)已是最新版本或更高版本。"
    exit 0
  fi
fi

# 创建用户级别的bin目录
mkdir -p ~/bin

# 创建darrenagent.sh脚本
cat <<EOL > ~/bin/darrenagent.sh
#!/bin/bash

# 获取系统信息
get_system_info() {
    memory=\$(free -m | awk 'NR==2{printf "Memory Usage: %s/%sMB (%.2f%%)\n", \$3,\$2,\$3*100/\$2 }')
    cpu=\$(top -bn1 | grep load | awk '{printf "CPU Load: %.2f\n", \$(NF-2)}')
    disk=\$(df -h | awk '\$NF=="/"{printf "Disk Usage: %d/%dGB (%s)\n", \$3,\$2,\$5}')
    ip=\$(hostname -I | awk '{print \$1}')
    process_count=\$(ps aux | wc -l)

    info=\$(printf '{"memory":"%s","cpu":"%s","disk":"%s","ip":"%s","process_count":"%s"}' "\$memory" "\$cpu" "\$disk" "\$ip" "\$process_count")
    echo \$info
}

# 生成MD5哈希
generate_md5() {
    echo -n "\$1" | md5sum | awk '{print \$1}'
}

# 发送系统信息到Web API
send_system_info() {
    info=\$(get_system_info)
    ts=\$(date +%s)
    token=\$(generate_md5 "\$SEC_KEY\$ts")
    response=\$(curl -s -X POST -H "Content-Type: application/json" -d "\$(printf '{"server":"%s","ip":"%s","data":"%s","ts":"%s","token":"%s"}' "\$(hostname)" "\$(hostname -I | awk '{print \$1}')" "\$info" "\$ts" "\$token")" \$API_URL)
    echo "Response: \$response"
}

# 主函数
while true; do
    send_system_info
    sleep \$SYNC_INTERVAL  # 每\$SYNC_INTERVAL秒同步一次
done
EOL

# 赋予脚本执行权限
chmod +x ~/bin/darrenagent.sh

# 创建用户级别的Systemd目录
mkdir -p ~/.config/systemd/user

# 创建Systemd服务文件
cat <<EOL > ~/.config/systemd/user/darrenagent.service
[Unit]
Description=System Info Sync Daemon $VERSION
After=network.target

[Service]
ExecStart=$HOME/bin/darrenagent.sh
Restart=always

[Install]
WantedBy=default.target
EOL

# 重新加载Systemd用户配置并启动服务
systemctl --user daemon-reload
systemctl --user start darrenagent.service
systemctl --user enable darrenagent.service

echo "darrenagent $VERSION 安装完成并已启动。"