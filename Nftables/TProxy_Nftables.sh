#!/bin/bash

# =================================================================
# Sing-box TProxy + Nftables 完整部署脚本 (v2)
# 适配系统: Debian / Ubuntu
# 功能:
# 1. 自动安装 nftables, iproute2
# 2. 写入内核转发配置 (sysctl)
# 3. 写入 nftables 规则 (包含 PREROUTING, OUTPUT, 和 FORWARD)
# 4. 创建 systemd 服务，在开机 30 秒后自动应用 TProxy 路由
# =================================================================

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 错误：此脚本必须以 root 权限运行。"
  exit 1
fi

echo "🚀 (1/7) 正在更新软件包列表并安装依赖..."
apt-get update
apt-get install -y nftables iproute2 curl

if [ $? -ne 0 ]; then
    echo "❌ 依赖安装失败。请检查你的 apt 源。"
    exit 1
fi

echo "✅ 依赖安装完毕。"
echo "---"

# -----------------------------------------------------
echo "⚙️ (2/7) 正在配置内核转发 (sysctl)..."
# -----------------------------------------------------
cat > /etc/sysctl.d/99-singbox-tproxy.conf << 'EOF'
# 启用 sing-box TProxy 所需的 IP 转发
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF

# 立即生效
sysctl -p /etc/sysctl.d/99-singbox-tproxy.conf
echo "✅ 内核转发已启用并设为永久。"
echo "---"

# -----------------------------------------------------
echo "📝 (3/7) 正在写入 nftables 配置文件 (/etc/nftables.conf)..."
# -----------------------------------------------------
# [注意] 这将覆盖 /etc/nftables.conf
cat > /etc/nftables.conf << 'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet singbox {

    # --- IP 地址集 (根据你的 config.json 修正) ---

    set china_dns_ipv4 {
        type ipv4_addr;
        elements = { 202.96.134.33, 223.5.5.5, 223.6.6.6, 114.114.114.114, 114.114.115.115 };
    }
    set china_dns_ipv6 {
        type ipv6_addr;
        elements = { 2400:3200::1, 2400:3200:baba::1 };
    }
    set fake_ipv4 {
        type ipv4_addr;
        flags interval;
        elements = { 198.18.0.0/15 }; # 对应 config.json
    }
    set fake_ipv6 {
        type ipv6_addr;
        flags interval;
        elements = { fc00::/18 }; # 对应 config.json
    }
    set local_ipv4 {
        type ipv4_addr;
        flags interval;
        elements = {
            0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12,  224.0.0.0/4, 240.0.0.0/4 };
    }
    set local_ipv6 {
        type ipv6_addr;
        flags interval;
        elements = {
            ::ffff:0.0.0.0/96, 64:ff9b::/96, 100::/64, 2001::/32, 2001:10::/28, 2001:20::/28, 2001:db8::/32, 2002::/16, fe80::/10 };
    }

    # --- 豁免规则 (用于所有链) ---
    chain tproxy-bypass {
        # 豁免宿主机本地流量 (关键规则)
        fib daddr type { unspec, local, anycast, multicast } return
        # 豁免私有地址 (包括 Docker 网段)
        ip daddr @local_ipv4 return
        ip6 daddr @local_ipv6 return
        # 豁免国内 DNS
        ip daddr @china_dns_ipv4 return
        ip6 daddr @china_dns_ipv6 return
        # 豁免 NTP
        udp dport {123} return
    }

    # --- TProxy 转发链 (TCP) ---
    chain tproxy-tcp-do {
        # 先检查豁免
        goto tproxy-bypass
        # 标记并转发 TCP
        meta l4proto tcp meta mark set 1 tproxy to :9420 accept # 对应 config.json 端口 9420
    }
    
    # --- TProxy 转发链 (UDP) ---
    chain tproxy-udp-do {
        # 先检查豁免
        goto tproxy-bypass
        # 标记并转发 UDP
        meta l4proto udp meta mark set 1 tproxy to :9420 accept # 对应 config.json 端口 9420
    }

    # --- 1. PREROUTING 钩子 (处理局域网流量) ---
    chain tproxy-prerouting {
        type filter hook prerouting priority mangle; policy accept;
        # TCP
        meta l4proto tcp ct direction original goto tproxy-tcp-do
        # UDP
        meta l4proto udp ct direction original goto tproxy-udp-do
    }

    # --- 2. OUTPUT 钩子 (处理宿主机和 FakeIP 流量) ---
    chain tproxy-output {
        type route hook output priority mangle; policy accept;
        
        # 豁免 sing-box 自身 (如果 sing-box GID 为 1)
        # (注意: TCP FakeIP 必须被转发, 不能豁免)
        meta l4proto udp skgid != 1 ct direction original goto tproxy-udp-mark
        
        # TCP: 只处理 FakeIP (访问本地服务已在 tproxy-tcp-mark 中通过 @local_ipv4 豁免)
        ip daddr @fake_ipv4 meta l4proto tcp meta mark set 1 tproxy to :9420 accept
        ip6 daddr @fake_ipv6 meta l4proto tcp meta mark set 1 tproxy to :9420 accept
    }

    chain tproxy-udp-mark {
        # 豁免私有地址和 DNS
        goto tproxy-bypass
        # 标记
        meta mark set 1
    }

    # --- 3. FORWARD 钩子 (新增: 处理 Docker 容器流量) ---
    chain tproxy-forward {
        type filter hook forward priority mangle; policy accept;
        # TCP
        meta l4proto tcp ct direction original goto tproxy-tcp-do
        # UDP
        meta l4proto udp ct direction original goto tproxy-udp-do
    }
}
EOF
echo "✅ nftables 规则已写入 (已包含 FORWARD 链)。"
echo "---"

# -----------------------------------------------------
echo "🛣️ (4/7) 正在创建 TProxy 策略路由脚本..."
# -----------------------------------------------------
# 创建一个可重入的脚本 (检查规则是否存在)
cat > /usr/local/sbin/apply_tproxy_routing.sh << 'EOF_RULES'
#!/bin/bash
# TProxy 策略路由配置脚本

# 1. 定义 TProxy 路由表
# 检查路由表 'singbox' (ID 100) 是否存在
if ! grep -q "100 singbox" /etc/iproute2/rt_tables; then
  echo "100 singbox" >> /etc/iproute2/rt_tables
fi

# 2. 添加 IPv4 规则：将 fwmark 1 的流量路由到 singbox 表
# 检查规则是否已存在
ip rule | grep -q "fwmark 1 lookup singbox" || ip rule add fwmark 1 lookup singbox
# 在 singbox 表中，添加一个本地默认路由，将流量交给 lo 接口
ip route show table singbox | grep -q "local default dev lo" || ip route add local default dev lo table singbox

# 3. 添加 IPv6 规则：同上
ip -6 rule | grep -q "fwmark 1 lookup singbox" || ip -6 rule add fwmark 1 lookup singbox
ip -6 route show table singbox | grep -q "local default dev lo" || ip -6 route add local default dev lo table 100

echo "✅ TProxy 策略路由已应用。"
EOF_RULES

# 赋予执行权限
chmod +x /usr/local/sbin/apply_tproxy_routing.sh
echo "✅ 策略路由脚本已创建。"
echo "---"

# -----------------------------------------------------
echo "⏳ (5/7) 正在创建 systemd 服务 (开机 30 秒延迟启动)..."
# -----------------------------------------------------
cat > /etc/systemd/system/singbox-tproxy-setup.service << 'EOF_SERVICE'
[Unit]
Description=Apply Sing-box TProxy Routing Rules (with delay)
# 确保在网络和 nftables 之后运行
# 最好是在 sing-box 服务启动之后 (如果你的服务叫 sing-box.service)
# After=network-online.target nftables.service sing-box.service
# Wants=sing-box.service
After=network-online.target nftables.service
Wants=network-online.target

[Service]
Type=oneshot
# 关键：执行前延迟 30 秒，等待 sing-box 启动
ExecStartPre=/bin/sleep 30
# 执行我们的策略路由脚本
ExecStart=/usr/local/sbin/apply_tproxy_routing.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF_SERVICE
echo "✅ systemd 服务已创建。"
echo "---"

# -----------------------------------------------------
echo "🟢 (6/7) 正在启用并立即启动服务 (应用规则)..."
# -----------------------------------------------------
systemctl daemon-reload

# 启用 nftables 服务 (开机加载 /etc/nftables.conf)
systemctl enable nftables.service
# 启用我们的 TProxy 路由服务 (开机 30s 后运行)
systemctl enable singbox-tproxy-setup.service

# 立即应用规则 (本次启动)
echo "正在立即应用 nftables 规则..."
systemctl restart nftables.service
if [ $? -ne 0 ]; then
    echo "❌ nftables 规则应用失败。请检查 /etc/nftables.conf 语法。"
    exit 1
fi

echo "正在立即应用 TProxy 策略路由..."
/usr/local/sbin/apply_tproxy_routing.sh
echo "✅ 所有服务已启用并立即应用。"
echo "---"

# -----------------------------------------------------
echo "🎉 (7/7) 部署完成！"
# -----------------------------------------------------
echo "TProxy 现已配置完毕，并已支持 Docker 容器流量。"
echo "下次重启时，系统将在启动 30 秒后自动应用 TProxy 路由规则。"
echo "请确保你的 TProxy服务  也在开机时启动。"