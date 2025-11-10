#!/bin/bash

#=================================================================================
#   Mihomo / Sing-box TProxy 模块化安装脚本
#
#   整合了 Scu x Duang 的 Mihomo 全家桶脚本 和 Sing-box 二进制安装逻辑
#   V5 版: (根据用户反馈)
#   1. 将 Sing-box 核心 URL 移至顶部配置区，方便修改。
#   2. 为 Sing-box 全家桶的成功信息添加 "联系作者" 部分。
#=================================================================================

# --- 脚本配置 (Mihomo 专用) ---
CONFIG_ZIP_URL="https://shangkouyou.lanzouo.com/iAb3u39mthef"
PLACEHOLDER_IP="10.0.0.121"

# --- 脚本配置 (Sing-box 专用) ---
# (请确保在更换版本时, 三个架构的链接都已更新)
SINGBOX_AMD64_URL="https://ghfast.top/github.com/Scu9277/TProxy/releases/download/sing-box/sing-box-1.13.0-alpha.27-reF1nd-linux-amd64"
SINGBOX_AMD64V3_URL="https://ghfast.top/github.com/Scu9277/TProxy/releases/download/sing-box/sing-box-1.13.0-alpha.27-reF1nd-linux-amd64v3"
SINGBOX_ARM64_URL="https://ghfast.top/github.com/Scu9277/TProxy/releases/download/sing-box/sing-box-1.13.0-alpha.27-reF1nd-linux-arm64"


# --- 脚本设置 ---
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[34m"
NC="\033[0m"
set -e
LAN_IP=""
MIHOMO_ARCH=""
SINGBOX_ARCH=""

#=================================================================================
#   SECTION 1: 共享组件 (可被所有选项调用)
#=================================================================================

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}❌ 错误：此脚本必须以 root 权限运行！${NC}"
        exit 1
    fi
}

# 检查并安装依赖
check_dependencies() {
    echo -e "🔍 正在检查系统依赖 (wget, curl, jq, unzip, hostname)..."
    DEPS=("wget" "curl" "jq" "unzip" "hostname" "grep")
    MISSING_DEPS=()

    for dep in "${DEPS[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            MISSING_DEPS+=("$dep")
        fi
    done

    if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
        echo -e "${YELLOW}🔧 检测到缺失的依赖: ${MISSING_DEPS[*]} ... 正在尝试自动安装...${NC}"
        if command -v apt-get > /dev/null; then
            apt-get update -y
            apt-get install -y "${MISSING_DEPS[@]}"
        else
            echo -e "${RED}❌ 无法自动安装依赖。请手动安装: ${MISSING_DEPS[*]} ${NC}"
            exit 1
        fi
        echo -e "${GREEN}✅ 核心依赖已安装完毕！${NC}"
    else
        echo -e "${GREEN}👍 依赖检查通过，全部已安装。${NC}"
    fi
    echo "----------------------------------------------------------------"
}

# ----------------------------------------------------------------
#   组件 1: DNS 劫持 (来自 Mihomo 脚本)
# ----------------------------------------------------------------
install_dns_hijack() {
    echo -e "${BLUE}--- 正在安装 [组件 6: DNS 劫持] ---${NC}"
    echo -e "📝 正在配置 /etc/hosts (本机劫持)..."
    if grep -q "scu.lan" /etc/hosts; then
        echo -e "${GREEN}👍 /etc/hosts 似乎已配置，跳过。${NC}"
        echo "----------------------------------------------------------------"
        return
    fi
    cat << 'EOF' | tee -a /etc/hosts > /dev/null

# --- Scu x Duang DNS Hijack (Local) ---
127.0.0.1   21.cn 21.com scu.cn scu.com shangkouyou.cn shangkouyou.com
127.0.0.1   21.icu scu.icu shangkouyou.icu
127.0.0.1   21.wifi scu.wifi shangkouyou.wifi
127.0.0.1   21.lan scu.lan shangkouyou.lan
EOF
    echo -e "${GREEN}✅ /etc/hosts 配置完毕。${NC}"
    echo "----------------------------------------------------------------"
}

# ----------------------------------------------------------------
#   组件 2: Docker (来自 Mihomo 脚本)
# ----------------------------------------------------------------
install_docker() {
    echo -e "${BLUE}--- 正在安装 [组件 3: Docker] ---${NC}"
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}👍 Docker 已经安装，跳过此步骤。${NC}"
        echo "----------------------------------------------------------------"
        return
    fi
    echo -e "🐳 正在执行 Docker 安装脚本 (linuxmirrors.cn/docker.sh)..."
    bash <(curl -sSL https://linuxmirrors.cn/docker.sh)
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker 安装失败！ 'docker' 命令不可用。${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Docker 安装成功。${NC}"
    echo "----------------------------------------------------------------"
}

# ----------------------------------------------------------------
#   组件 3: Sub-Store (来自 Mihomo 脚本)
# ----------------------------------------------------------------
install_substore() {
    echo -e "${BLUE}--- 正在安装 [组件 4: Sub-Store] ---${NC}"
    CONTAINER_NAME="sub-store"
    IMAGE_NAME="xream/sub-store:latest"

    if [ $(docker ps -q -f name=^/${CONTAINER_NAME}$) ]; then
        echo -e "${GREEN}👍 Sub-Store 容器 'sub-store' 已经在运行，跳过。${NC}"
        echo "----------------------------------------------------------------"
        return
    fi

    if [ $(docker ps -a -q -f name=^/${CONTAINER_NAME}$) ]; then
        echo -e "${YELLOW}🔄 发现已停止的 'sub-store' 容器，正在尝试启动...${NC}"
        docker start $CONTAINER_NAME
        sleep 3
        if [ $(docker ps -q -f name=^/${CONTAINER_NAME}$) ]; then
             echo -e "${GREEN}✅ Sub-Store 容器启动成功！${NC}"
             echo "----------------------------------------------------------------"
             return
        else
             echo -e "${RED}❌ 启动失败，正在移除旧容器并重新创建...${NC}"
             docker rm $CONTAINER_NAME
        fi
    fi

    if ! docker images -q $IMAGE_NAME | grep -q . ; then
        echo -e "${YELLOW}🔎 未找到 '$IMAGE_NAME' 镜像，正在下载...${NC}"
        echo -e "📦 正在下载 Sub-Store Docker 镜像包..."
        wget "https://ghfast.top/github.com/Scu9277/TProxy/releases/download/1.0/sub-store.tar.gz" -O "/root/sub-store.tar.gz"
        echo -e "🗜️ 正在解压并加载镜像..."
        tar -xzf "/root/sub-store.tar.gz" -C "/root/"
        docker load -i "/root/sub-store.tar"
        rm -f "/root/sub-store.tar.gz" "/root/sub-store.tar"
    else
        echo -e "${GREEN}👍 发现 '$IMAGE_NAME' 镜像，跳过下载。${NC}"
    fi

    echo -e "🚀 正在启动 Sub-Store 容器..."
    docker run -it -d --restart=always \
      -e "SUB_STORE_BACKEND_SYNC_CRON=55 23 * * *" \
      -e "SUB_STORE_FRONTEND_BACKEND_PATH=/21DEDINGZHI" \
      -p 0.0.0.0:9277:3001 \
      -v /root/sub-store-data:/opt/app/data \
      --name $CONTAINER_NAME \
      $IMAGE_NAME
    echo -e "⏳ 正在等待 Sub-Store 容器启动 (5秒)..."
    sleep 5
    if [ $(docker ps -q -f name=^/${CONTAINER_NAME}$) ]; then
        echo -e "${GREEN}✅ Sub-Store 容器已成功启动 (端口 9277)！${NC}"
    else
        echo -e "${RED}❌ Sub-Store 容器启动失败！${NC}"
    fi
    echo "----------------------------------------------------------------"
}

# ----------------------------------------------------------------
#   组件 4: TProxy (Mihomo 专用脚本, Sing-box 将复用此脚本)
# ----------------------------------------------------------------
install_tproxy_mihomo() {
    echo -e "${BLUE}--- 正在安装 [组件 5: TProxy (tproxy_mihomo-1.sh)] ---${NC}"
    if [ -f "/etc/systemd/system/tproxy-rules.service" ]; then
        echo -e "${GREEN}👍 TProxy systemd service 已存在，假定 TProxy 已安装，跳过。${NC}"
        echo -e "${YELLOW}如需重新运行 TProxy 脚本，请先手动删除 /etc/systemd/system/tproxy-rules.service 再执行${NC}"
        echo "----------------------------------------------------------------"
        return
    fi
    echo -e "🔧 准备执行 TProxy 脚本 (tproxy_mihomo-1.sh)..."
    TPROXY_SCRIPT_URL="https://ghfast.top/https://raw.githubusercontent.com/Scu9277/TProxy/refs/heads/main/tproxy_mihomo-1.sh"
    bash <(curl -sSL "$TPROXY_SCRIPT_URL")
    echo -e "${GREEN}✅ TProxy 脚本 (tproxy_mihomo-1.sh) 执行完毕！${NC}"
    echo "----------------------------------------------------------------"
}


#=================================================================================
#   SECTION 2: 核心安装程序 (Core Installers)
#=================================================================================

# ----------------------------------------------------------------
#   核心 1: Mihomo 核心 (安装、配置、启动)
# ----------------------------------------------------------------
install_mihomo_core_and_config() {
    echo -e "${BLUE}--- 正在安装 [核心: Mihomo] ---${NC}"
    # 1. 检查配置 URL
    if [ -z "$CONFIG_ZIP_URL" ]; then
        echo -e "${RED}🛑 错误：Mihomo 的 'CONFIG_ZIP_URL' 未在脚本顶部配置！${NC}"
        exit 1
    fi

    # 2. 检查架构
    echo -e "🕵️  正在检测 Mihomo 所需架构..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) MIHOMO_ARCH="amd64-v2" ;;
        aarch64) MIHOMO_ARCH="arm64-v8" ;;
        armv7l) MIHOMO_ARCH="armv7" ;;
        *) echo -e "${RED}❌ 不支持的架构: $ARCH！${NC}"; exit 1 ;;
    esac
    echo -e "${GREEN}✅ Mihomo 架构: $MIHOMO_ARCH${NC}"

    # 3. 安装 Mihomo (如果未安装)
    if command -v mihomo &> /dev/null; then
        echo -e "${GREEN}👍 Mihomo 已经安装，跳过下载。${NC}"
        mihomo -v
    else
        echo -e "📡 正在获取 Mihomo 最新版本号..."
        API_URL="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
        LATEST_TAG=$(curl -sL $API_URL | jq -r .tag_name)
        if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" == "null" ]; then
            echo -e "${RED}❌ 获取 Mihomo 最新版本号失败！${NC}"; exit 1
        fi
        echo -e "${GREEN}🎉 找到最新版本: $LATEST_TAG${NC}"
        DEB_FILENAME="mihomo-linux-${MIHOMO_ARCH}-${LATEST_TAG}.deb"
        DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_TAG}/${DEB_FILENAME}"
        FAST_DOWNLOAD_URL="https://ghfast.top/${DOWNLOAD_URL}"
        DEB_PATH="/root/${DEB_FILENAME}"
        echo -e "🚀 正在下载: $FAST_DOWNLOAD_URL"
        wget -O "$DEB_PATH" "$FAST_DOWNLOAD_URL"
        dpkg -i "$DEB_PATH"
        rm -f "$DEB_PATH"
        mihomo -v
        echo -e "${GREEN}✅ Mihomo 安装成功！${NC}"
    fi

    # 4. 下载并配置 (带覆盖检查)
    if [ -f "/etc/mihomo/config.yaml" ]; then
        read -p "$(echo -e ${YELLOW}"⚠️  检测到已存在的 Mihomo 配置文件，是否覆盖? (y/N): "${NC})" choice
        case "$choice" in
          y|Y ) echo "🔄 好的，将继续下载并覆盖配置..." ;;
          * ) echo -e "${GREEN}👍 保留现有配置，跳过下载。${NC}"; return ;;
        esac
    fi
    echo -e "📂 正在配置您的 mihomo 配置文件..."
    API_RESOLVE_URL="https://api.zxki.cn/api/lzy?url=${CONFIG_ZIP_URL}"
    REAL_DOWN_URL=$(curl -sL "$API_RESOLVE_URL" | jq -r .downUrl)
    if [ -z "$REAL_DOWN_URL" ] || [ "$REAL_DOWN_URL" == "null" ]; then
        echo -e "${RED}❌ 错误：无法从 API 解析到下载地址！${NC}"; exit 1
    fi
    CONFIG_ZIP_PATH="/root/mihomo_config.zip"
    TEMP_DIR="/root/mihomo_temp_unzip"
    wget -O "$CONFIG_ZIP_PATH" "$REAL_DOWN_URL"
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    unzip -o "$CONFIG_ZIP_PATH" -d "$TEMP_DIR"
    if [ -d "$TEMP_DIR/mihomo" ]; then
        rm -rf /etc/mihomo
        mv "$TEMP_DIR/mihomo" /etc/
    elif [ -f "$TEMP_DIR/config.yaml" ]; then
        mkdir -p /etc/mihomo
        mv "$TEMP_DIR"/* /etc/mihomo/
    else
        echo -e "${RED}❌ 错误：无法识别的 ZIP 压缩包结构！${NC}"; exit 1
    fi
    rm -f "$CONFIG_ZIP_PATH"
    rm -rf "$TEMP_DIR"
    echo -e "${GREEN}✅ 配置文件部署成功！${NC}"

    # 5. 配置 DNS 劫持 (替换 IP)
    echo -e "📡 正在获取本机局域网 IP (用于 DNS 劫持)..."
    LAN_IP=$(hostname -I | awk '{print $1}')
    if [ -z "$LAN_IP" ]; then
        echo -e "${RED}❌ 未能自动获取局域网 IP！${NC}"; exit 1
    fi
    echo -e "${GREEN}✅ 本机 IP: $LAN_IP${NC}"
    CONFIG_FILE="/etc/mihomo/config.yaml"
    if grep -q "$PLACEHOLDER_IP" "$CONFIG_FILE"; then
        echo -e "🔍 发现占位符 ${PLACEHOLDER_IP}，正在替换为 ${GREEN}${LAN_IP}${NC}..."
        sed -i "s/${PLACEHOLDER_IP}/${LAN_IP}/g" "$CONFIG_FILE"
        echo -e "${GREEN}✅ 占位符 IP 替换成功！${NC}"
    else
        echo -e "${GREEN}👍 未在 $CONFIG_FILE 中检测到占位符，假定已配置。${NC}"
    fi

    # 6. 启动 Mihomo 服务
    echo -e "🚀 正在启动并设置 mihomo 服务为开机自启..."
    systemctl enable mihomo
    systemctl restart mihomo
    sleep 3
    if systemctl is-active --quiet mihomo; then
        echo -e "${GREEN}✅ Mihomo 服务正在愉快地运行！${NC}"
    else
        echo -e "${RED}❌ Mihomo 服务启动失败！${NC}"; exit 1
    fi
    echo "----------------------------------------------------------------"
}

# ----------------------------------------------------------------
#   核心 2: Sing-box 核心 (安装、配置、启动)
# ----------------------------------------------------------------
install_singbox_core_and_config() {
    echo -e "${BLUE}--- 正在安装 [核心: Sing-box] ---${NC}"

    # 1. 检测架构
    echo -e "${YELLOW}正在检测 Sing-box 所需架构...${NC}"
    ARCH_RAW=$(uname -m)
    if [ "$ARCH_RAW" == "x86_64" ] || [ "$ARCH_RAW" == "amd64" ]; then
        if command -v grep > /dev/null && [ -f /proc/cpuinfo ] && grep -q avx2 /proc/cpuinfo; then
            SINGBOX_ARCH="amd64v3"
        else
            SINGBOX_ARCH="amd64"
        fi
    elif [ "$ARCH_RAW" == "aarch64" ] || [ "$ARCH_RAW" == "arm64" ]; then
        SINGBOX_ARCH="arm64"
    else
        echo -e "${RED}错误：不支持的系统架构 $ARCH_RAW。${NC}"; exit 1
    fi
    echo -e "${GREEN}检测到架构: $SINGBOX_ARCH${NC}"

    # 2. 定义路径和 URL
    INSTALL_DIR="/usr/local/bin"
    CONFIG_DIR="/etc/sing-box"
    SINGBOX_CORE_PATH="$INSTALL_DIR/sing-box"
    
    # 【【【 V5 变更 】】】从顶部配置获取 URL
    SINGBOX_DOWNLOAD_URL=""
    case "$SINGBOX_ARCH" in
        amd64) SINGBOX_DOWNLOAD_URL="$SINGBOX_AMD64_URL" ;;
        amd64v3) SINGBOX_DOWNLOAD_URL="$SINGBOX_AMD64V3_URL" ;;
        arm64) SINGBOX_DOWNLOAD_URL="$SINGBOX_ARM64_URL" ;;
    esac
    
    if [ -z "$SINGBOX_DOWNLOAD_URL" ]; then
        echo -e "${RED}错误：无法根据架构 $SINGBOX_ARCH 匹配到下载 URL。请检查顶部配置。${NC}"
        exit 1
    fi

    # 3. 停止服务 (如果正在运行)，以避免 "Text file busy"
    if systemctl is-active --quiet sing-box; then
        echo -e "${YELLOW}正在停止正在运行的 Sing-box 服务以更新核心...${NC}"
        systemctl stop sing-box
    fi
    
    # 4. 下载核心
    echo -e "${YELLOW}正在下载 Sing-box 核心 ($SINGBOX_ARCH)...${NC}"
    mkdir -p $INSTALL_DIR
    curl -L -o "$SINGBOX_CORE_PATH" "$SINGBOX_DOWNLOAD_URL"
    chmod +x $SINGBOX_CORE_PATH
    echo -e "${GREEN}Sing-box 核心安装成功!${NC}"
    $SINGBOX_CORE_PATH version

    # 5. 下载配置
    mkdir -p $CONFIG_DIR
    CONFIG_JSON_URL="https://ghfast.top/raw.githubusercontent.com/Scu9277/TProxy/refs/heads/main/sing-box/config.json"
    echo -e "${YELLOW}正在下载 Sing-box 配置文件...${NC}"
    curl -L -o "$CONFIG_DIR/config.json" "$CONFIG_JSON_URL"
    echo -e "${GREEN}config.json 下载成功！${NC}"
    
    # 6. 创建并启动 Systemd 服务
    echo "正在创建 systemd 服务..."
    cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=Sing-Box Service
After=network.target network-online.target
Wants=network-online.target
[Service]
Type=simple
LimitNPROC=512
LimitNOFILE=1048576
ExecStart=$SINGBOX_CORE_PATH run -c $CONFIG_DIR/config.json
Restart=on-failure
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable sing-box
    echo -e "${YELLOW}正在启动 Sing-box 服务...${NC}"
    systemctl restart sing-box
    sleep 2
    if systemctl is-active --quiet sing-box; then
        echo -e "${GREEN}✅ Sing-box 服务已成功启动！${NC}"
    else
        echo -e "${RED}❌ Sing-box 服务启动失败！${NC}"; exit 1
    fi
    echo "----------------------------------------------------------------"
}

#=================================================================================
#   SECTION 3: 全家桶安装程序 (Full Stacks)
#=================================================================================

# ----------------------------------------------------------------
#   全家桶 1: Mihomo
# ----------------------------------------------------------------
install_full_stack_mihomo() {
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}  开始安装 [选项 1: Mihomo 全家桶] ${NC}"
    echo -e "${GREEN}==========================================${NC}"
    
    # 1. 更换系统源 (Mihomo 脚本特有)
    echo -e "🔧 正在执行换源脚本 (linuxmirrors.cn/main.sh)..."
    bash <(curl -sSL https://linuxmirrors.cn/main.sh)
    echo -e "${GREEN}✅ 换源脚本执行完毕。${NC}"
    echo "----------------------------------------------------------------"
    
    # 2. 安装组件
    install_dns_hijack
    install_docker
    install_substore
    
    # 3. 安装 Mihomo 核心、配置并启动
    install_mihomo_core_and_config
    
    # 4. 安装 Mihomo TProxy
    install_tproxy_mihomo
    
    # 5. 打印最终信息
    (
    echo "================================================================"
    echo -e "🎉 ${GREEN}哇哦！Mihomo 全家桶全部搞定！${NC} 🎉"
    echo -e "DNS 劫持已启用！局域网设备 DNS 设为 ${YELLOW}${LAN_IP}${NC} 即可访问。"
    echo ""
    echo -e "--- ${BLUE}Mihomo (仪表盘) ${NC}---"
    echo -e "Mihomo UI: ${YELLOW}http://scu.lan/ui${NC} (或 21.cn/ui 等)"
    echo -e "--- ${BLUE}Sub-Store (订阅管理) ${NC}---"
    echo -e "Sub-Store UI: ${YELLOW}http://scu.lan:9277/${NC} (或 21.cn:9277/ 等)"
    echo ""
    echo -e "--- ${BLUE}联系作者 (可定制) ${NC}---"
    echo -e "💬 微信: ${YELLOW}shangkouyou${NC}"
    echo "================================================================"
    ) | tee /root/ScuDEDINGZHI_Mihomo.txt
}

# ----------------------------------------------------------------
#   全家桶 2: Sing-box
# ----------------------------------------------------------------
install_full_stack_singbox() {
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}  开始安装 [选项 2: Sing-box 全家桶] ${NC}"
    echo -e "${GREEN}==========================================${NC}"
    
    # 1. 安装共享组件
    install_dns_hijack  # (复用)
    install_docker      # (复用)
    install_substore    # (复用)
    
    # 2. 安装 Sing-box 核心、配置并启动
    install_singbox_core_and_config
    
    # 3. 安装 TProxy (复用 Mihomo 脚本)
    install_tproxy_mihomo
    
    # 4. 打印最终信息
    (
    echo "================================================================"
    echo -e "🎉 ${GREEN}Sing-box 全家桶已安装！${NC} 🎉"
    echo -e "Docker, Sub-Store, DNS 劫持, TProxy 均已启动。"
    echo -e "Sing-box 核心已启动。"
    echo ""
    echo -e "--- ${BLUE}TProxy 状态 ${NC}---"
    echo -e "已复用 Mihomo TProxy 脚本 (tproxy_mihomo-1.sh)。"
    echo -e "请您自行确保此脚本与您的 Sing-box 配置兼容。"
    echo ""
    echo -e "--- ${BLUE}Sing-box (无UI) ${NC}---"
    echo -e "状态: ${GREEN}已运行${NC}"
    echo -e "--- ${BLUE}Sub-Store (订阅管理) ${NC}---"
    echo -e "Sub-Store UI: ${YELLOW}http://scu.lan:9277/${NC} (或 21.cn:9277/ 等)"
    echo ""
    echo -e "--- ${BLUE}联系作者 (可定制) ${NC}---" # 【【【 V5 变更 】】】
    echo -e "💬 微信: ${YELLOW}shangkouyou${NC}"    # 【【【 V5 变更 】】】
    echo "================================================================"
    ) | tee /root/ScuDEDINGZHI_Singbox.txt
}

#=================================================================================
#   SECTION 4: 主菜单 (Main Menu)
#=================================================================================

# 主菜单
main_menu() {
    clear
    echo "=================================================="
    echo "     Mihomo / Sing-box 模块化安装脚本 (V5)"
    echo "         (整合自 Scu x Duang 脚本)"
    echo "=================================================="
    echo
    echo "请选择要执行的操作:"
    echo -e "--- ${GREEN}全家桶 (推荐) ${NC}---"
    echo "  1) 安装 Mihomo 全家桶 (Docker + Sub-Store + TProxy + DNS劫持)"
    echo "  2) 安装 Sing-box 全家桶 (Docker + Sub-Store + TProxy + DNS劫持)"
    echo -e "--- ${YELLOW}单独安装组件 ${NC}---"
    echo "  3) 安装 Docker"
    echo "  4) 安装 Sub-Store (需 Docker)"
    echo "  5) 安装 TProxy (tproxy内核转发"
    echo "  6) 安装 DNS 劫持 (/etc/hosts)"
    echo "--------------------------------------------------"
    echo "  7) 退出脚本"
    echo
    read -p "请输入选项 [1-7]: " choice

    case $choice in
        1)
            install_full_stack_mihomo
            ;;
        2)
            install_full_stack_singbox
            ;;
        3)
            install_docker
            ;;
        4.
            install_substore
            ;;
        5)
            install_tproxy_mihomo
            ;;
        6)
            install_dns_hijack
            ;;
        7)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请输入 1 到 7。${NC}"
            sleep 2
            ;;
    esac
    
    if [ "$choice" != "7" ]; then
        # 循环显示主菜单，除非选择退出
        read -p "按任意键返回主菜单..."
        main_menu
    fi
}

# --- 脚本开始执行 ---
check_root
check_dependencies
main_menu
