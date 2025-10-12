#!/bin/bash

# ==============================
# Debian/Ubuntu 网络配置助手（安全版）
# 功能: DHCP -> 静态IP交互式配置 + IP检查 + 自动应用检测
# ==============================

GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

NETPLAN_FILE="/etc/network/interfaces"

# 检测活跃网卡
echo -e "${GREEN}检测当前活跃网络接口...${RESET}"
interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo))
active_interfaces=()
for iface in "${interfaces[@]}"; do
    if ip addr show "$iface" | grep -q "inet "; then
        active_interfaces+=("$iface")
    fi
done

if [ ${#active_interfaces[@]} -eq 0 ]; then
    echo -e "${RED}未检测到活跃网络接口，退出.${RESET}"
    exit 1
fi

echo -e "${YELLOW}活跃网络接口列表:${RESET}"
for i in "${!active_interfaces[@]}"; do
    echo "$i) ${active_interfaces[$i]}"
done

read -rp "请选择要修改的网卡编号: " iface_index
iface="${active_interfaces[$iface_index]}"
echo -e "${GREEN}您选择的网卡是: $iface${RESET}"

# 交互式输入 IP
while true; do
    read -rp "请输入静态IP地址 (例如 192.168.1.100): " static_ip
    [[ -z "$static_ip" ]] && echo -e "${RED}IP不能为空${RESET}" && continue

    # IP 格式验证
    function validate_ip() {
        local ip=$1
        if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            for i in $(echo $ip | tr '.' ' '); do
                if ((i < 0 || i > 255)); then
                    return 1
                fi
            done
            return 0
        else
            return 1
        fi
    }

    if ! validate_ip "$static_ip"; then
        echo -e "${RED}IP格式不正确${RESET}"
        continue
    fi

    # 检测 IP 是否被占用
    ping -c 1 -W 1 "$static_ip" &> /dev/null
    if [ $? -eq 0 ]; then
        echo -e "${RED}IP $static_ip 已被占用，请选择其他 IP${RESET}"
        continue
    fi
    break
done

read -rp "请输入子网掩码位数 [默认24]: " netmask
netmask=${netmask:-24}
read -rp "请输入网关地址 (可选): " gateway
if [ -n "$gateway" ] && ! validate_ip "$gateway"; then
    echo -e "${RED}网关格式不正确，忽略网关设置${RESET}"
    gateway=""
fi
read -rp "请输入首选DNS [默认 119.29.29.29]: " dns1
dns1=${dns1:-119.29.29.29}
read -rp "请输入备用DNS [默认 8.8.8.8]: " dns2
dns2=${dns2:-8.8.8.8}

# 显示配置预览
echo -e "${YELLOW}配置预览:${RESET}"
echo "网卡: $iface"
echo "IP: $static_ip/$netmask"
echo "网关: $gateway"
echo "DNS: $dns1 $dns2"

read -rp "确认无误后才应用配置，是否继续？[y/N]: " confirm
[[ ! "$confirm" =~ ^[Yy]$ ]] && echo "取消操作" && exit 0

# 备份原始配置
backup_file="${NETPLAN_FILE}.bak.$(date +%F_%T)"
cp "$NETPLAN_FILE" "$backup_file"
echo -e "${GREEN}已备份原配置: $backup_file${RESET}"

# 生成新配置
cat > "$NETPLAN_FILE" <<EOL
auto lo
iface lo inet loopback

allow-hotplug $iface
iface $iface inet static
    address $static_ip/$netmask
EOL

[ -n "$gateway" ] && echo "    gateway $gateway" >> "$NETPLAN_FILE"
echo "    dns-nameservers $dns1 $dns2" >> "$NETPLAN_FILE"
echo "iface $iface inet6 auto" >> "$NETPLAN_FILE"

# 应用配置
echo -e "${YELLOW}应用配置并重启网卡...${RESET}"
if ip link show "$iface" | grep -q "state UP"; then
    ifdown "$iface" 2>/dev/null
fi
ifup "$iface" 2>/dev/null

# 检查 IP 是否生效
if ! ip addr show "$iface" | grep -q "$static_ip"; then
    echo -e "${YELLOW}尝试重启 networking 服务...${RESET}"
    systemctl restart networking
    sleep 2
fi

if ip addr show "$iface" | grep -q "$static_ip"; then
    echo -e "${GREEN}网卡 $iface 已成功应用新 IP: $static_ip${RESET}"
else
    echo -e "${RED}配置未生效，请检查网络${RESET}"
fi

# 网络连通性检测
ping_target=${gateway:-"8.8.8.8"}
ping -c 3 -W 2 "$ping_target" &> /dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}网络通畅: $ping_target 可达${RESET}"
else
    echo -e "${RED}网络不通: $ping_target 不可达${RESET}"
    read -rp "是否回滚配置？[y/N]: " rollback
    if [[ "$rollback" =~ ^[Yy]$ ]]; then
        cp "$backup_file" "$NETPLAN_FILE"
        ifdown "$iface" 2>/dev/null
        ifup "$iface" 2>/dev/null
        echo -e "${GREEN}已回滚原配置${RESET}"
    fi
fi

echo -e "${GREEN}操作完成${RESET}"
