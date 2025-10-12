# 一键执行完整流程（直接直接复制全部内容粘贴到终端）
echo "=============================================="
echo "  Mihomo TProxy 透明代理一键脚本"
echo "  支持: Debian 12+ / Ubuntu 22.04+"
echo "  Duang x Scu 一键搭建定制化脚本 +WX:shangkouyou"
echo "=============================================="

set -euo pipefail

# 创建目录
mkdir -p /etc/tproxy

# 写入规则脚本
cat > /etc/tproxy/tproxy.sh << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/tproxy-rules.log"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始加载TProxy规则" >> "${LOG_FILE}"

# 检测网络接口
MAIN_IF=$(ip -4 route show default | grep -oP '(?<=dev )\S+' | head -n1)
if [[ -z "${MAIN_IF}" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误：无法检测主网卡" >> "${LOG_FILE}"
    exit 1
fi

MAIN_IP=$(ip -4 addr show "${MAIN_IF}" | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n1)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 检测到主网卡: ${MAIN_IF} (${MAIN_IP})" >> "${LOG_FILE}"

# 清理旧规则
iptables -t mangle -F 2>/dev/null || echo "清理mangle表失败" >> "${LOG_FILE}"
iptables -t mangle -X MIHOMO 2>/dev/null || echo "删除MIHOMO链失败" >> "${LOG_FILE}"
iptables -t nat -F PREROUTING 2>/dev/null || echo "清理nat表失败" >> "${LOG_FILE}"

# 创建新规则
iptables -t mangle -N MIHOMO && echo "创建MIHOMO链成功" >> "${LOG_FILE}" || echo "创建MIHOMO链失败" >> "${LOG_FILE}"
iptables -t mangle -A MIHOMO -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A MIHOMO -d 192.168.0.0/16 -j RETURN
iptables -t mangle -A MIHOMO -d 127.0.0.0/8 -j RETURN
iptables -t mangle -A MIHOMO -p tcp -j TPROXY --on-port 9420 --tproxy-mark 0x2333
iptables -t mangle -A MIHOMO -p udp -j TPROXY --on-port 9420 --tproxy-mark 0x2333
iptables -t mangle -A PREROUTING -j MIHOMO
iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53

# 配置路由
ip rule add fwmark 0x2333 table 100 2>/dev/null || echo "添加路由规则失败（已存在）" >> "${LOG_FILE}"
ip route add local default dev lo table 100 2>/dev/null || echo "添加本地路由失败（已存在）" >> "${LOG_FILE}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 规则加载完成" >> "${LOG_FILE}"
EOF

# 赋予脚本权限
chmod +x /etc/tproxy/tproxy.sh
touch /var/log/tproxy-rules.log

# 配置内核参数
cat > /etc/sysctl.d/99-tproxy.conf << 'EOF'
# =======================
# BBR 拥塞控制优化
# =======================
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# =======================
# IPv4 路由转发
# =======================
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.accept_local = 1
# =======================
# IPv6 路由转发
# =======================
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1

# 保持物理网卡 enp2s0 在 forwarding 开启时仍接受上游的 RA
net.ipv6.conf.ens18.accept_ra = 2
EOF
sysctl -p /etc/sysctl.d/99-tproxy.conf >/dev/null 2>&1

# 安装依赖
apt-get update -qq >/dev/null 2>&1 || true
apt-get install -y iptables iproute2 net-tools curl ca-certificates >/dev/null 2>&1

# 创建服务
cat > /etc/systemd/system/tproxy-rules.service << 'EOF'
[Unit]
Description=TProxy Rules Auto-Load Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sleep 30 && /etc/tproxy/tproxy.sh'
RemainAfterExit=yes
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF

# 启用服务
systemctl daemon-reload
systemctl enable tproxy-rules.service >/dev/null 2>&1
systemctl start tproxy-rules.service

# 立即执行一次规则
/etc/tproxy/tproxy.sh

# 输出结果
echo "=========================================="
echo "✅ 部署完成！"
echo "规则脚本: /etc/tproxy/tproxy.sh"
echo "服务名称: tproxy-rules"
echo "重启后验证: iptables -t mangle -L MIHOMO -n"
echo "=========================================="
echo "安装完成！现在可以配置客户端使用透明代理了"
echo "=========================================="
echo "需要技术支持在线可联系📮shangkouyou@gmail.com"
echo "=========================================="