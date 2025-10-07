#!/bin/bash
# =====================================================
# Sing-Box TProxy 一键部署脚本（IPv4 + IPv6 + 自动检测恢复）
# 适用于 Debian 12+ / Ubuntu 22+
# 作者: Duang X Scu
# =====================================================

set -e

echo "🔧 开始部署 Sing-Box TProxy 环境（IPv4 + IPv6 + 自愈检测）..."

# 1️⃣ 安装依赖
apt update -y
apt install -y iptables iproute2 iptables-persistent curl

# 2️⃣ 创建目录
mkdir -p /etc/tproxy

# =====================================================
# 3️⃣ 创建规则脚本
# =====================================================
cat > /etc/tproxy/tproxy.sh <<'EOF'
#!/bin/bash
# ========== Sing-Box TProxy IPv4 + IPv6 配置脚本（自愈版） ==========

LOG_FILE="/var/log/tproxy.log"
exec > >(tee -a $LOG_FILE) 2>&1

echo "🕒 [$(date)] 开始加载 TProxy 规则..."

# 检查是否存在 tproxy 二进制端口占用
TPROXY_PORT=7894

# 清空旧规则
iptables -t mangle -F
ip6tables -t mangle -F
iptables -t nat -F
ip6tables -t nat -F

# =====================================================
# IPv4 路由策略
# =====================================================
ip rule add fwmark 1 table 100 2>/dev/null || true
ip route add local 0.0.0.0/0 dev lo table 100 2>/dev/null || true

# IPv6 路由策略
ip -6 rule add fwmark 1 table 100 2>/dev/null || true
ip -6 route add local ::/0 dev lo table 100 2>/dev/null || true

# =====================================================
# IPv4 规则
# =====================================================
iptables -t mangle -N SING_BOX 2>/dev/null || true
iptables -t mangle -F SING_BOX

iptables -t mangle -A SING_BOX -d 0.0.0.0/8 -j RETURN
iptables -t mangle -A SING_BOX -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A SING_BOX -d 127.0.0.0/8 -j RETURN
iptables -t mangle -A SING_BOX -d 169.254.0.0/16 -j RETURN
iptables -t mangle -A SING_BOX -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A SING_BOX -d 192.168.0.0/16 -j RETURN
iptables -t mangle -A SING_BOX -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A SING_BOX -d 240.0.0.0/4 -j RETURN

iptables -t mangle -A SING_BOX -p tcp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark 1
iptables -t mangle -A SING_BOX -p udp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark 1

iptables -t mangle -C PREROUTING -j SING_BOX 2>/dev/null || \
iptables -t mangle -A PREROUTING -j SING_BOX

# =====================================================
# IPv6 规则
# =====================================================
ip6tables -t mangle -N SING_BOX 2>/dev/null || true
ip6tables -t mangle -F SING_BOX

ip6tables -t mangle -A SING_BOX -d ::1/128 -j RETURN
ip6tables -t mangle -A SING_BOX -d fe80::/10 -j RETURN
ip6tables -t mangle -A SING_BOX -d fc00::/7 -j RETURN
ip6tables -t mangle -A SING_BOX -d ff00::/8 -j RETURN

ip6tables -t mangle -A SING_BOX -p tcp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark 1
ip6tables -t mangle -A SING_BOX -p udp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark 1

ip6tables -t mangle -C PREROUTING -j SING_BOX 2>/dev/null || \
ip6tables -t mangle -A PREROUTING -j SING_BOX

# =====================================================
# 启用内核参数
# =====================================================
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.route_localnet=1
sysctl -w net.ipv6.conf.all.forwarding=1

# 保存规则
netfilter-persistent save

echo "✅ [$(date)] IPv4 + IPv6 TProxy 规则已加载完成！"
EOF

chmod +x /etc/tproxy/tproxy.sh

# =====================================================
# 4️⃣ 创建检测与自动恢复脚本
# =====================================================
cat > /etc/tproxy/tproxy-check.sh <<'EOF'
#!/bin/bash
# ========== Sing-Box TProxy 检测与自动恢复脚本 ==========

LOG_FILE="/var/log/tproxy-check.log"
exec > >(tee -a $LOG_FILE) 2>&1

check_and_reload() {
    local proto=$1
    local cmd=$2

    echo "🔍 检查 ${proto} 规则状态..."

    if ! $cmd -t mangle -L SING_BOX &>/dev/null; then
        echo "⚠️ 检测到 ${proto} TProxy 规则缺失，正在重新加载..."
        bash /etc/tproxy/tproxy.sh
    else
        if ! $cmd -t mangle -L SING_BOX -v -n | grep -q "TPROXY"; then
            echo "⚠️ 检测到 ${proto} TProxy 规则异常，重新加载中..."
            bash /etc/tproxy/tproxy.sh
        else
            echo "✅ ${proto} TProxy 规则正常。"
        fi
    fi
}

check_and_reload "IPv4" "iptables"
check_and_reload "IPv6" "ip6tables"
EOF

chmod +x /etc/tproxy/tproxy-check.sh

# =====================================================
# 5️⃣ 创建 systemd 服务：规则加载 + 定时检测
# =====================================================
cat > /etc/systemd/system/tproxy.service <<'EOF'
[Unit]
Description=Sing-Box TProxy 规则加载（IPv4 + IPv6 + 自动检测）
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/tproxy/tproxy.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/tproxy-check.timer <<'EOF'
[Unit]
Description=定期检测并自动恢复 TProxy 规则

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=tproxy-check.service

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/tproxy-check.service <<'EOF'
[Unit]
Description=Sing-Box TProxy 自动检测与恢复
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/tproxy/tproxy-check.sh
EOF

# =====================================================
# 6️⃣ 启用服务与定时检测
# =====================================================
systemctl daemon-reload
systemctl enable tproxy.service
systemctl enable tproxy-check.timer
systemctl start tproxy.service
systemctl start tproxy-check.timer

# =====================================================
# 7️⃣ 显示结果
# =====================================================
echo
echo "✅ 部署完成！"
echo "   规则脚本: /etc/tproxy/tproxy.sh"
echo "   检测脚本: /etc/tproxy/tproxy-check.sh"
echo "   主服务状态: systemctl status tproxy.service"
echo "   定时检测: systemctl list-timers | grep tproxy"
echo
echo "📜 日志文件:"
echo "   /var/log/tproxy.log"
echo "   /var/log/tproxy-check.log"
EOF
