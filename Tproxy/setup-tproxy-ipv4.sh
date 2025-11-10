#!/bin/bash
# ==========================================
# 🧠 Sing-box IPv4 TProxy 一键配置脚本（链名: TPROXY）
# 作者：shangkouyou
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

echo "[$(date '+%F %T')] 🚀 开始配置 IPv4 TProxy 环境..." | tee -a "$LOG_FILE"

# ---- 创建目录 ----
mkdir -p "$TPROXY_DIR"

# ---- 检查包管理器 ----
if command -v apt >/dev/null 2>&1; thenÍ
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
if iptables --version 2>&1 | grep -q "nf_tables"; then
  if command -v iptables-legacy >/dev/null 2>&1; then
    update-alternatives --set iptables /usr/sbin/iptables-legacy || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true
    echo "[$(date '+%F %T')] 🔁 已切换到 iptables-legacy 模式" | tee -a "$LOG_FILE"
  else
    echo "[$(date '+%F %T')] ⚠️ 当前为 nftables 模式，将尝试兼容执行" | tee -a "$LOG_FILE"
  fi
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
# IPv4-only TProxy for sing-box
LOG_FILE="/var/log/tproxy.log"
TPROXY_PORT=$TPROXY_PORT
TPROXY_MARK=$TPROXY_MARK
TABLE_ID=$TABLE_ID
DOCKER_PORT=$DOCKER_PORT

echo "[$(date '+%F %T')] 开始加载 IPv4 TProxy 规则..." | tee -a "\$LOG_FILE"

MAIN_IF=\$(ip -4 route show default | grep -oP '(?<=dev )\\S+' | head -n1)
MAIN_IP=\$(ip -4 addr show "\$MAIN_IF" | grep inet | awk '{print \$2}' | cut -d/ -f1 | head -n1)
echo "检测到主网卡: \$MAIN_IF (\$MAIN_IP)" | tee -a "\$LOG_FILE"

iptables -t mangle -F
iptables -t mangle -X TPROXY 2>/dev/null
iptables -t mangle -N TPROXY

# 豁免本地、局域网、Docker 订阅端口 9277
for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8 255.255.255.255; do
  iptables -t mangle -A TPROXY -d \$net -j RETURN
done
iptables -t mangle -A TPROXY -p tcp --dport \$DOCKER_PORT -j RETURN
iptables -t mangle -A TPROXY -p udp --dport \$DOCKER_PORT -j RETURN

# 添加 TProxy 转发
iptables -t mangle -A TPROXY -p tcp -j TPROXY --on-port \$TPROXY_PORT --tproxy-mark \$TPROXY_MARK
iptables -t mangle -A TPROXY -p udp -j TPROXY --on-port \$TPROXY_PORT --tproxy-mark \$TPROXY_MARK
iptables -t mangle -I PREROUTING -j TPROXY

# 策略路由
ip rule add fwmark \$TPROXY_MARK table \$TABLE_ID 2>/dev/null
ip route add local default dev lo table \$TABLE_ID 2>/dev/null

echo "[$(date '+%F %T')] ✅ IPv4 TProxy 规则加载完成" | tee -a "\$LOG_FILE"
EOF

chmod +x "$TPROXY_SCRIPT"
echo "[$(date '+%F %T')] ✅ 写入转发脚本到 $TPROXY_SCRIPT" | tee -a "$LOG_FILE"

# ---- 创建 systemd 服务 ----
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Sing-box IPv4 TProxy Redirect Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$TPROXY_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tproxy.service
systemctl start tproxy.service
echo "[$(date '+%F %T')] ✅ 已创建并启动 systemd 服务 tproxy.service" | tee -a "$LOG_FILE"

# ---- 验证结果 ----
echo "[$(date '+%F %T')] 🔍 当前 TProxy 状态:" | tee -a "$LOG_FILE"
iptables -t mangle -L PREROUTING -v | tee -a "$LOG_FILE"
iptables -t mangle -L TPROXY -v | tee -a "$LOG_FILE"
ip rule show | tee -a "$LOG_FILE"
ip route show table 100 | tee -a "$LOG_FILE"

echo "[$(date '+%F %T')] 🎉 IPv4 TProxy 已配置完成！配置文件: $TPROXY_SCRIPT" | tee -a "$LOG_FILE"
echo "日志文件: $LOG_FILE"
