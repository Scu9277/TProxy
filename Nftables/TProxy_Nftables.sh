#!/bin/bash

# =================================================================
# Sing-box TProxy + Nftables 最终部署脚本 (v9)
# 适配系统: Debian Trixie (内核限制版)
#
# !! 重要 !!
# 此脚本基于我们之前的调试，仅配置了 PREROUTING 钩子。
# 这意味着:
# ✅ 局域网其他设备可以被透明代理。
# ❌ 宿主机本身 (OUTPUT) 无法被代理。
# ❌ Docker 容器 (FORWARD) 无法被代理。
# =================================================================

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 错误：此脚本必须以 root 权限运行。"
  exit 1
fi

echo "🚀 (1/8) 正在更新软件包列表并安装依赖..."
apt-get update
apt-get install -y nftables iproute2 curl

if [ $? -ne 0 ]; then
    echo "❌ 依赖安装失败。请检查你的 apt 源。"
    exit 1
fi
echo "✅ 依赖安装完毕。"
echo "---"

# -----------------------------------------------------
echo "⚙️ (2/8) 正在加载 conntrack 内核模块 (关键修复)..."
# -----------------------------------------------------
# 立即手动加载 conntrack 内核模块
modprobe nf_conntrack
# 创建一个配置文件，让系统在开机时自动加载此模块
echo "nf_conntrack" > /etc/modules-load.d/singbox-tproxy.conf
echo "✅ 内核模块 'nf_conntrack' 已加载并设为永久。"
echo "---"

# -----------------------------------------------------
echo "⚙️ (3/8) 正在配置内核转发 (sysctl)..."
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
echo "📝 (4/8) 正在写入 nftables 配置文件 (v9 - 仅 Prerouting)..."
# -----------------------------------------------------
# [注意] 这将覆盖 /etc/nftables.conf
cat > /etc/nftables.conf << 'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet singbox {

    # --- IP 地址集 ---

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

    # --- 1. PREROUTING 钩子 (v9: 纯粹的顺序逻辑) ---
    # 这是唯一能在你的内核上运行的链
    chain tproxy-prerouting {
        type filter hook prerouting priority mangle; policy accept;
        
        # 1. 豁免已建立的连接
        ct state { established, related } return
        
        # 2. 豁免本地/DNS/NTP
        ip daddr @local_ipv4 return
        ip6 daddr @local_ipv6 return
        ip daddr @china_dns_ipv4 return
        ip6 daddr @china_dns_ipv6 return
        meta l4proto udp udp dport {123} return
        
        # 3. 转发 TCP (新连接)
        meta l4proto tcp meta protocol ip meta mark set 1 tproxy ip to :9420 accept
        meta l4proto tcp meta protocol ip6 meta mark set 1 tproxy ip6 to :9420 accept

        # 4. 转发 UDP (新连接)
        meta l4proto udp meta protocol ip meta mark set 1 tproxy ip to :9420 accept
        meta l4proto udp meta protocol ip6 meta mark set 1 tproxy ip6 to :9420 accept
    }

    # --- OUTPUT 和 FORWARD 钩子均因内核不支持而移除 ---
}
EOF
echo "✅ nftables 规则 (v9) 已写入。"
echo "---"

# -----------------------------------------------------
echo "🛣️ (5/8) 正在创建 TProxy 策略路由脚本..."
# -----------------------------------------------------
cat > /usr/local/sbin/apply_tproxy_routing.sh << 'EOF_RULES'
#!/bin/bash
# TProxy 策略路由配置脚本

# 1. 定义 TProxy 路由表 'singbox' (ID 100)
if ! grep -q "100 singbox" /etc/iproute2/rt_tables; then
  echo "100 singbox" >> /etc/iproute2/rt_tables
fi

# 2. 添加 IPv4 规则
ip rule | grep -q "fwmark 1 lookup singbox" || ip rule add fwmark 1 lookup singbox
ip route show table singbox | grep -q "local default dev lo" || ip route add local default dev lo table singbox

# 3. 添加 IPv6 规则
ip -6 rule | grep -q "fwmark 1 lookup singbox" || ip -6 rule add fwmark 1 lookup singbox
ip -6 route show table singbox | grep -q "local default dev lo" || ip -6 route add local default dev lo table 100

echo "✅ TProxy 策略路由已应用。"
EOF_RULES

# 赋予执行权限
chmod +x /usr/local/sbin/apply_tproxy_routing.sh
echo "✅ 策略路由脚本已创建。"
echo "---"

# -----------------------------------------------------
echo "⏳ (6/8) 正在创建 systemd 服务 (开机 30 秒延迟启动)..."
# -----------------------------------------------------
cat > /etc/systemd/system/singbox-tproxy-setup.service << 'EOF_SERVICE'
[Unit]
Description=Apply Sing-box TProxy Routing Rules (with delay)
After=network-online.target nftables.service
Wants=network-online.target
# 如果你的 sing-box 服务也叫 sing-box.service，取消下面两行的注释
# Wants=sing-box.service
# After=sing-box.service

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
echo "🟢 (7/8) 正在启用并立即启动服务 (应用规则)..."
# -----------------------------------------------------
systemctl daemon-reload

# 启用 nftables 服务 (开机加载 /etc/nftables.conf)
systemctl enable nftables.service
# 启用我们的 TProxy 路由服务 (开机 30s 后运行)
systemctl enable singbox-tproxy-setup.service

# 立即应用规则 (本次启动)
echo "正在立即应用 nftables 规则..."
systemctl restart nftables.service

# 检查 nftables 是否成功
if [ $? -ne 0 ]; then
    echo "❌ nftables 服务启动失败！"
    echo "请运行 'journalctl -xeu nftables.service' 再次检查日志。"
    exit 1
fi

echo "正在立即应用 TProxy 策略路由..."
/usr/local/sbin/apply_tproxy_routing.sh
echo "✅ 所有服务已启用并立即应用。"
echo "---"

# -----------------------------------------------------
echo "🎉 (8/8) 部署完成！"
# -----------------------------------------------------
echo ""
echo "⚠️ 重要提示 (内核限制):"
echo "此配置仅代理您【局域网中的其他设备】 (PREROUTING)。"
echo "由于您的 Debian Trixie 内核限制，它 ❌ 不会 ❌ 代理:"
echo "  1. 宿主机本身 (OUTPUT 钩子不可用)"
echo "  2. Docker 容器 (FORWARD 钩子不可用)"
echo ""
echo "下次重启时，系统将在启动 30 秒后自动应用局域网代理规则。"
echo "请确保你的 TProxy 已经启动，并监端口。"
