#!/bin/bash
# ==========================================
# 🧠 Sing-box IPv4 TProxy 一键配置脚本
# 作者：shangkouyou
# (由 Gemini 修复 V3 - 修复 TPROXY 链名称冲突)
# ==========================================

set -e
LOG_FILE="/var/log/tproxy-setup.log"
TPROXY_DIR="/etc/tproxy"
TPROXY_SCRIPT="$TPROXY_DIR/tproxy.sh"
SERVICE_FILE="/etc/systemd/system/tproxy.service"
TPROXY_PORT=9420
TPROXY_MARK=0x2333
TABLE_ID=100
DOCKER_PORT=9277

# !! 修复点：定义一个不与内核目标冲突的自定义链名称
CUSTOM_CHAIN="TPROXY_CHAIN"

echo "[$(date '+%F %T')] 🚀 开始配置 IPv4 TProxy 环境 (仅网关模式)..." | tee -a "$LOG_FILE"

# ---- 创建目录 ----
mkdir -p "$TPROXY_DIR"

# ---- 检查包管理器 ----
if command -v apt >/dev/null 2>&1; then
  PKG_INSTALL="apt install -y"
  PKG_UPDATE="apt update -y"
elif command -v apk >/dev/null 2>&1; then
  PKG_INSTALL="apk add"
  PKG_UPDATE="apk update"
elif command -v dnf >/dev/null 2>&1; then
  PKG_INSTALL="dnf install -y"
  PKG_UPDATE="dnf makecache"
elif command -v yum >/dev/null 2>&1; then
  PKG_INSTALL="yum install -y"
  PKG_UPDATE="yum makecache"
else
  echo "❌ 无法识别包管理器，请手动安装 iptables/iproute2/systemd" | tee -a "$LOG_FILE"
  exit 1
fi

# ---- 检查并安装依赖 ----
REQUIRED_PKGS=(iptables iproute2 systemd)
MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! command -v "$pkg" >/dev/null 2>&1; then
    MISSING_PKGS+=("$pkg")
  fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
  echo "[$(date '+%F %T')] 📦 检测到缺失依赖: ${MISSING_PKGS[*]}" | tee -a "$LOG_FILE"
  $PKG_UPDATE && $PKG_INSTALL "${MISSING_PKGS[@]}"
else
  echo "[$(date '+%F %T')] ✅ 所有依赖已安装" | tee -a "$LOG_FILE"
fi

# ---- 切换到 iptables-legacy (若存在) ----
# Debian 13 (Trixie) 默认使用 nftables，TProxy 必须用 legacy
if command -v update-alternatives >/dev/null 2>&1; then
  if command -v iptables-legacy >/dev/null 2>&1; then
    update-alternatives --set iptables /usr/sbin/iptables-legacy || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true
    echo "[$(date '+%F %T')] 🔁 已强制切换到 iptables-legacy 模式" | tee -a "$LOG_FILE"
  else
     echo "[$(date '+%F %T')] ⚠️ 未找到 iptables-legacy，TProxy 可能会失败" | tee -a "$LOG_FILE"
  fi
else
    echo "[$(date '+%F %T')] ⚠️ 非 Debian/Ubuntu 系统，请手动确保使用 iptables-legacy" | tee -a "$LOG_FILE"
fi

# ---- 加载内核模块 ----
for mod in xt_TPROXY nf_tproxy_ipv4; do
  modprobe $mod 2>/dev/null && echo "[$(date '+%F %T')] ✅ 加载模块: $mod" | tee -a "$LOG_FILE"
done

# ---- 启用 IPv4 转发 ----
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf && sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
echo "[$(date '+%F %T')] 🔧 已启用 IPv4 转发" | tee -a "$LOG_FILE"

# ---- 写入 IPv4 TProxy 脚本 ----
cat > "$TPROXY_SCRIPT" <<EOF
#!/bin/bash
# IPv4-only TProxy for sing-box (Gateway/PREROUTING Only)
# ** 修复：使用 $CUSTOM_CHAIN 代替 TPROXY 作为链名称 **
LOG_FILE="/var/log/tproxy.log"
TPROXY_PORT=$TPROXY_PORT
TPROXY_MARK=$TPROXY_MARK
TABLE_ID=$TABLE_ID
DOCKER_PORT=$DOCKER_PORT
CHAIN_NAME="$CUSTOM_CHAIN"

echo "[$(date '+%F %T')] 开始加载 IPv4 TProxy 规则 (链: \$CHAIN_NAME)..." | tee -a "\$LOG_FILE"

MAIN_IF=\$(ip -4 route show default | grep -oP '(?<=dev )\\S+' | head -n1)
MAIN_IP=\$(ip -4 addr show "\$MAIN_IF" | grep inet | awk '{print \$2}' | cut -d/ -f1 | head -n1)
echo "检测到主网卡: \$MAIN_IF (\$MAIN_IP)" | tee -a "\$LOG_FILE"

# ---- 安全清理旧规则 ----
# 清理跳转规则
iptables -t mangle -D PREROUTING -j \$CHAIN_NAME 2>/dev/null || true
# 清空并删除旧链
iptables -t mangle -F \$CHAIN_NAME 2>/dev/null || true
iptables -t mangle -X \$CHAIN_NAME 2>/dev/null || true
# 清理策略路由
ip rule del fwmark \$TPROXY_MARK table \$TABLE_ID 2>/dev/null || true
ip route flush table \$TABLE_ID 2>/dev/null || true

# ---- 创建新链 ----
iptables -t mangle -N \$CHAIN_NAME

# ---- 规则详情 ----

# 1. 豁免本地、局域网、Docker 订阅端口 9277
for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8 255.255.255.255; do
  iptables -t mangle -A \$CHAIN_NAME -d \$net -j RETURN
done
# 豁免服务器本身的 IP，防止来自局域网的回环
iptables -t mangle -A \$CHAIN_NAME -d \$MAIN_IP -j RETURN

iptables -t mangle -A \$CHAIN_NAME -p tcp --dport \$DOCKER_PORT -j RETURN
iptables -t mangle -A \$CHAIN_NAME -p udp --dport \$DOCKER_PORT -j RETURN

# 2. 添加 TProxy 转发 (!! 重点：-j TPROXY 是指内核的 *目标* !!)
iptables -t mangle -A \$CHAIN_NAME -p udp --dport 443 -j REJECT
iptables -t mangle -A \$CHAIN_NAME -p tcp -j TPROXY --on-port \$TPROXY_PORT --tproxy-mark \$TPROXY_MARK
iptables -t mangle -A \$CHAIN_NAME -p udp -j TPROXY --on-port \$TPROXY_PORT --tproxy-mark \$TPROXY_MARK

# 3. Hook 链 (!! 重点：跳转到我们的 *自定义链* !!)
iptables -t mangle -I PREROUTING -j \$CHAIN_NAME

# 4. 策略路由
ip rule add fwmark \$TPROXY_MARK table \$TABLE_ID
ip route add local default dev lo table \$TABLE_ID

echo "[$(date '+%F %T')] ✅ IPv4 TProxy 规则加载完成 (链: \$CHAIN_NAME)" | tee -a "\$LOG_FILE"
EOF

chmod +x "$TPROXY_SCRIPT"
echo "[$(date '+%F %T')] ✅ 写入转发脚本到 $TPROXY_SCRIPT" | tee -a "$LOG_FILE"

# ---- 创建 systemd 服务 ----
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Sing-box IPv4 TProxy Redirect Service (Gateway Mode)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 30
ExecStart=$TPROXY_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tproxy.service
systemctl restart tproxy.service

# ---- 检查服务状态 ----
if systemctl is-active --quiet tproxy.service; then
  echo "[$(date '+%F %T')] ✅ 已创建并成功启动 systemd 服务 tproxy.service" | tee -a "$LOG_FILE"
else
  echo "[$(date '+%F %T')] ❌ 服务 tproxy.service 启动失败！" | tee -a "$LOG_FILE"
  echo "请手动执行 'journalctl -xeu tproxy.service' 检查错误。" | tee -a "$LOG_FILE"
  exit 1
fi

# ---- 验证结果 ----
echo "[$(date '+%F %T')] 🔍 当前 TProxy 状态:" | tee -a "$LOG_FILE"
iptables -t mangle -L PREROUTING -v -n | tee -a "$LOG_FILE"
# !! 修复点：验证我们正确的自定义链
iptables -t mangle -L $CUSTOM_CHAIN -v -n | tee -a "$LOG_FILE"
ip rule show | tee -a "$LOG_FILE"
ip route show table 100 | tee -a "$LOG_FILE"

echo "[$(date '+%F %T')] 🎉 IPv4 TProxy 已配置完成 (仅网关模式)！" | tee -a "$LOG_FILE"
echo "日志文件: $LOG_FILE 和 /var/log/tproxy.log"
echo "✅ 执行过程中遇到的任何问题都可以联系我。"
echo "✅ 宿主机流量不会被代理。"
