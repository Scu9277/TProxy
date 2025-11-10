#!/bin/bash
echo "=============================================="
echo " 🚀 Mihomo TProxy 一键透明代理部署脚本"
echo " 支持: Debian 12+ / Ubuntu 22.04+"
echo " 作者: Duang x Scu   联系: shangkouyou@gmail.com"
echo " (已修复: 增加 9277 端口豁免 + 兼容 Docker NAT 规则)"
echo "=============================================="
set -e

# ---------- 通用函数 ----------
log_step() { echo -e "\n🧩 $1 ..."; sleep 0.5; }
log_ok()   { echo "✅ $1"; }
log_fail() { echo "❌ $1"; }

# ---------- 检查 root ----------
if [[ $EUID -ne 0 ]]; then
  log_fail "请使用 root 权限执行"
  exit 1
fi

# ---------- 检查系统 ----------
log_step "检测系统版本"
if ! grep -Eiq "debian|ubuntu" /etc/os-release; then
  log_fail "不支持的系统，仅支持 Debian/Ubuntu"
  exit 1
else
  log_ok "系统兼容"
fi

# ---------- 检查并安装依赖 ----------
log_step "检查依赖包"
deps=(iptables iproute2 net-tools curl ca-certificates)
missing=()
for pkg in "${deps[@]}"; do
  dpkg -s "$pkg" &>/dev/null || missing+=("$pkg")
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "📦 缺少依赖: ${missing[*]}"
  log_step "正在安装依赖..."
  apt-get update -y >/dev/null
  apt-get install -y "${missing[@]}" >/dev/null && log_ok "依赖安装完成" || log_fail "依赖安装失败"
else
  log_ok "所有依赖均已安装"
fi

# ---------- 创建目录 ----------
log_step "创建目录与日志文件"
mkdir -p /etc/tproxy
touch /var/log/tproxy-rules.log
chmod 644 /var/log/tproxy-rules.log
log_ok "目录 /etc/tproxy 创建完成"

# ---------- 写入规则脚本 ----------
log_step "写入规则脚本 /etc/tproxy/tproxy.sh"
cat > /etc/tproxy/tproxy.sh << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/tproxy-rules.log"
echo "[$(date '+%F %T')] 开始加载TProxy规则" >> "$LOG_FILE"

MAIN_IF=$(ip -4 route show default | grep -oP '(?<=dev )\S+' | head -n1)
if [[ -z "$MAIN_IF" ]]; then
  echo "[$(date '+%F %T')] ❌ 未检测到主网卡" >> "$LOG_FILE"
  exit 1
fi

MAIN_IP=$(ip -4 addr show "$MAIN_IF" | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n1)
echo "[$(date '+%F %T')] 检测到主网卡: $MAIN_IF ($MAIN_IP)" >> "$LOG_FILE"

# --- Mangle 表清理 ---
iptables -t mangle -F 2>/dev/null
iptables -t mangle -X MIHOMO 2>/dev/null
iptables -t mangle -N MIHOMO 2>/dev/null && echo "创建MIHOMO链成功" >> "$LOG_FILE"

#修复
iptables -t mangle -I PREROUTING 1 -d 255.255.255.255 -j RETURN

# --- 豁免规则 (局域网/本机) ---
iptables -t mangle -A MIHOMO -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A MIHOMO -d 192.168.0.0/16 -j RETURN
iptables -t mangle -A MIHOMO -d 127.0.0.0/8 -j RETURN

#sing-box修复
iptables -t mangle -I PREROUTING 1 -p udp -d 255.255.255.255 --dport 5678 -j RETURN

# --- 豁免本机访问 Sub-Store (Docker) 的 9277 端口 ---
iptables -t mangle -I OUTPUT 1 -p tcp --dport 9277 -j ACCEPT
echo "[$(date '+%F %T')] (Mangle OUTPUT) 豁免本机访问 TCP 9277 端口" >> "$LOG_FILE"

# --- 关键：豁免 Sub-Store (Docker) 的 9277 端口 ---
# (此规则必须保留，否则 TProxy 会劫持流量)
iptables -t mangle -A MIHOMO -p tcp --dport 9277 -j RETURN
echo "[$(date '+%F %T')] (Mangle) 豁免 TCP 9277 端口 (Sub-Store)" >> "$LOG_FILE"

# --- TProxy 转发规则 ---
iptables -t mangle -A MIHOMO -p tcp -j TPROXY --on-port 9420 --tproxy-mark 0x2333
iptables -t mangle -A MIHOMO -p udp -j TPROXY --on-port 9420 --tproxy-mark 0x2333

# --- 应用 MIHOMO 链 ---
iptables -t mangle -A PREROUTING -j MIHOMO

# --- 关键：安全地添加 DNS 转发规则 (不清除 Docker 规则) ---
DNS_RULE_EXISTS=$(iptables -t nat -C PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53 &>/dev/null; echo $?)
if [ "$DNS_RULE_EXISTS" -ne 0 ]; then
    iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53
    echo "[$(date '+%F %T')] (Nat) 添加 DNS 转发规则" >> "$LOG_FILE"
else
    echo "[$(date '+%F %T')] (Nat) DNS 转发规则已存在，跳过。" >> "$LOG_FILE"
fi

# --- 策略路由 ---
ip rule add fwmark 0x2333 table 100 2>/dev/null
ip route add local default dev lo table 100 2>/dev/null

echo "[$(date '+%F %T')] 规则加载完成" >> "$LOG_FILE"
EOF
chmod +x /etc/tproxy/tproxy.sh
log_ok "规则脚本已生成 (已包含9277豁免 和 NAT修复)"

# ---------- 写入 sysctl ----------
log_step "写入系统内核优化配置"
cat > /etc/sysctl.d/99-tproxy.conf << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.accept_local = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-tproxy.conf >/dev/null
log_ok "内核参数已应用"

# ---------- 写入 systemd 服务 ----------
log_step "创建 systemd 服务"
cat > /etc/systemd/system/tproxy-rules.service << 'EOF'
[Unit]
Description=TProxy Rules Auto-Load Service
# 关键：确保在 Docker 之后启动，以便 Docker 先设置好 NAT 规则
After=network-online.target docker.service
Wants=network-online.target docker.service

[Service]
Type=oneshot
# 修复：移除 sleep 10，依赖 After=docker.service 更可靠
#ExecStart=/etc/tproxy/tproxy.sh
ExecStart=/bin/bash -c 'sleep 30 && /etc/tproxy/tproxy.sh'
RemainAfterExit=yes
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable tproxy-rules.service >/dev/null
log_ok "服务已创建并启用"

# ---------- 重启服务并立即加载 ----------
log_step "重启 Docker (确保 NAT 规则) 并加载 TProxy 规则"
# (为确保万无一失，最好重启 Docker)
systemctl restart docker.service
log_ok "Docker 重启完毕"
sleep 3
systemctl restart tproxy-rules.service
/etc/tproxy/tproxy.sh && log_ok "TProxy 规则已加载完成"

# ---------- 最后提示 ----------
echo "=========================================="
echo "✅ 部署完成！"
echo "规则脚本: /etc/tproxy/tproxy.sh"
echo "服务名称: tproxy-rules"
echo "查看日志: tail -f /var/log/tproxy-rules.log"
echo "验证规则: iptables -t mangle -L MIHOMO -n"
echo " (请检查 9277 端口的 RETURN 规则)"
echo "=========================================="
