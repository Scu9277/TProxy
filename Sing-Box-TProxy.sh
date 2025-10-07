#!/bin/bash
# =====================================================
# Sing-Box TProxy 一键部署脚本（IPv4 + IPv6）
# 适用于 Debian 12+ / Ubuntu 22+
# 作者: Duang x Scu
# =====================================================

set -e

echo "🔧 开始部署 Sing-Box TProxy 环境（IPv4 + IPv6）..."

# 1️⃣ 安装依赖
apt update -y
apt install -y iptables iproute2 iptables-persistent

# 2️⃣ 创建目录
mkdir -p /etc/tproxy

# 3️⃣ 创建规则脚本
cat > /etc/tproxy/tproxy.sh <<'EOF'
#!/bin/bash
# ========== Sing-Box TProxy IPv4 + IPv6 配置脚本 ==========

echo "⚙️ 清空旧规则..."
iptables -t mangle -F
ip6tables -t mangle -F
iptables -t nat -F
ip6tables -t nat -F

echo "🛠️ 设置策略路由表..."
# IPv4
ip rule add fwmark 1 table 100 2>/dev/null || true
ip route add local 0.0.0.0/0 dev lo table 100 2>/dev/null || true
# IPv6
ip -6 rule add fwmark 1 table 100 2>/dev/null || true
ip -6 route add local ::/0 dev lo table 100 2>/dev/null || true

# =====================================================
# IPv4 TPROXY 规则
# =====================================================
echo "📦 创建 IPv4 SING_BOX 链..."
iptables -t mangle -N SING_BOX 2>/dev/null || true
iptables -t mangle -F SING_BOX

# 局域网和保留网段免代理
iptables -t mangle -A SING_BOX -d 0.0.0.0/8 -j RETURN
iptables -t mangle -A SING_BOX -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A SING_BOX -d 127.0.0.0/8 -j RETURN
iptables -t mangle -A SING_BOX -d 169.254.0.0/16 -j RETURN
iptables -t mangle -A SING_BOX -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A SING_BOX -d 192.168.0.0/16 -j RETURN
iptables -t mangle -A SING_BOX -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A SING_BOX -d 240.0.0.0/4 -j RETURN

# 其他流量透明代理
iptables -t mangle -A SING_BOX -p tcp -j TPROXY --on-port 9420 --tproxy-mark 1
iptables -t mangle -A SING_BOX -p udp -j TPROXY --on-port 9420 --tproxy-mark 1

# 挂载到 PREROUTING
iptables -t mangle -C PREROUTING -j SING_BOX 2>/dev/null || \
iptables -t mangle -A PREROUTING -j SING_BOX


# =====================================================
# IPv6 TPROXY 规则
# =====================================================
echo "📦 创建 IPv6 SING_BOX 链..."
ip6tables -t mangle -N SING_BOX 2>/dev/null || true
ip6tables -t mangle -F SING_BOX

# 保留地址免代理
ip6tables -t mangle -A SING_BOX -d ::1/128 -j RETURN
ip6tables -t mangle -A SING_BOX -d fe80::/10 -j RETURN
ip6tables -t mangle -A SING_BOX -d fc00::/7 -j RETURN
ip6tables -t mangle -A SING_BOX -d ff00::/8 -j RETURN

# 其他流量透明代理
ip6tables -t mangle -A SING_BOX -p tcp -j TPROXY --on-port 9420 --tproxy-mark 1
ip6tables -t mangle -A SING_BOX -p udp -j TPROXY --on-port 9420 --tproxy-mark 1

# 挂载到 PREROUTING
ip6tables -t mangle -C PREROUTING -j SING_BOX 2>/dev/null || \
ip6tables -t mangle -A PREROUTING -j SING_BOX


# =====================================================
# 启用内核参数
# =====================================================
echo "🔧 启用内核转发..."
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.route_localnet=1
sysctl -w net.ipv6.conf.all.forwarding=1

# 保存规则
netfilter-persistent save

echo "✅ IPv4 + IPv6 TProxy 规则加载完成并保存成功！"
EOF

chmod +x /etc/tproxy/tproxy.sh

# 4️⃣ 创建 systemd 服务
cat > /etc/systemd/system/tproxy.service <<'EOF'
[Unit]
Description=Sing-Box TProxy 规则自启动（IPv4 + IPv6）
After=network-pre.target
Before=sing-box.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/tproxy/tproxy.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 5️⃣ 启用服务
systemctl daemon-reload
systemctl enable tproxy.service
systemctl start tproxy.service

# 6️⃣ 验证结果
echo
echo "🔍 当前 IPv4 TProxy 规则："
iptables -t mangle -L -n -v | grep TPROXY || echo "⚠️ 尚未检测到 IPv4 TPROXY 规则"
echo
echo "🔍 当前 IPv6 TProxy 规则："
ip6tables -t mangle -L -n -v | grep TPROXY || echo "⚠️ 尚未检测到 IPv6 TPROXY 规则"
echo
echo "✅ 部署完成！"
echo "   规则脚本: /etc/tproxy/tproxy.sh"
echo "   服务管理: systemctl status tproxy.service"
echo "   查看 IPv4 规则: iptables -t mangle -L -v -n"
echo "   查看 IPv6 规则: ip6tables -t mangle -L -v -n"
EOF
