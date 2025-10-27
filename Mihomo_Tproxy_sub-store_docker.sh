#!/bin/bash

#=================================================================================
#   _  _ ___   _   _ ___ ___ ___  ___ 
#  | \| | __| /_\ | | _ \ __/ __|/ __|
#  | .` | _| / _ \| |  _/ _|\__ \ (__ 
#  |_|\_|___/_/ \_\_|_| |___|___/\___|
#
#   Mihomo (MetaCubeX) + Docker + Sub-Store + TProxy 全自动安装脚本
#
#   作者: Scu 联合x Duang
#   邮箱: shangkouyou@gmail.com
#   微信: shangkouyou
#
#   感谢使用！遇到问题请通过上面的方式联系我。
#=================================================================================

# --- 脚本配置 ---

# 🛑🛑🛑【【【【 重要：请在这里填入你的蓝奏云分享链接 】】】】🛑🛑🛑
# 
# 脚本会通过 API 解析这个链接，下载ZIP包，并解压到 /etc/mihomo
#
# 示例: CONFIG_ZIP_URL="https://shangkouyou.lanzouo.com/iVTN338jiuih"
#
CONFIG_ZIP_URL="https://shangkouyou.lanzouo.com/iVTN338jiuih" 


# --- 脚本设置 ---

# 颜色定义
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[34m"
NC="\033[0m" # No Color

# 自动退出：任何命令失败则立即退出
set -e

# --- 功能函数 ---

# 打印作者信息
show_author_info() {
    clear
    echo -e "${BLUE}"
    echo "================================================================"
    echo "   _  _ ___   _   _ ___ ___ ___  ___ "
    echo "  | \| | __| /_\ | | _ \ __/ __|/ __|"
    echo "  | . \` | _| / _ \| |  _/ _|\__ \ (__ "
    echo "  |_|\_|___/_/ \_\_|_| |___|___/\___|"
    echo ""
    echo "     Mihomo (MetaCubeX) + Docker + Sub-Store + TProxy 全自动安装脚本"
    echo "================================================================"
    echo -e "${NC}"
    echo -e "👋 嗨！我是 ${GREEN}Scu 联合x Duang${NC}"
    echo -e "📧 邮箱: ${YELLOW}shangkouyou@gmail.com${NC}"
    echo -e "💬 微信: ${YELLOW}shangkouyou${NC}"
    echo ""
    echo "🚀 脚本马上开始执行，请坐和放宽..."
    echo "----------------------------------------------------------------"
    sleep 3
}

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}❌ 错误：此脚本必须以 root 权限运行！${NC}"
        echo -e "${YELLOW}请尝试使用 'sudo -i' 切换到 root 用户后再执行。${NC}"
        exit 1
    fi
}

# 检查并安装依赖
check_dependencies() {
    echo -e "🔍 正在检查系统依赖 (wget, curl, jq, unzip, hostname)..."
    # 移除 TProxy 相关的依赖 (假定 TProxy 脚本自处理)
    DEPS=("wget" "curl" "jq" "unzip" "hostname")
    MISSING_DEPS=()

    for dep in "${DEPS[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            MISSING_DEPS+=("$dep")
        fi
    done

    if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
        echo -e "${YELLOW}🔧 检测到缺失的依赖: ${MISSING_DEPS[*]} ... 正在尝试自动安装...${NC}"
        apt-get install -y "${MISSING_DEPS[@]}" || echo -e "${YELLOW}部分依赖安装可能失败，脚本继续...${NC}"
        
        CORE_DEPS=("wget" "curl" "jq" "unzip")
         for dep in "${CORE_DEPS[@]}"; do
            if ! command -v "$dep" &> /dev/null; then
                echo -e "${RED}❌ 核心依赖 $dep 安装失败！请手动安装后再试。${NC}"
                exit 1
            fi
        done
        echo -e "${GREEN}✅ 核心依赖已安装完毕！${NC}"
    else
        echo -e "${GREEN}👍 依赖检查通过，全部已安装。${NC}"
    fi
    echo "----------------------------------------------------------------"
}


# 检查配置文件URL
check_config_url() {
    if [ -z "$CONFIG_ZIP_URL" ]; then
        echo -e "${RED}🛑 错误：你还没有配置你的 'CONFIG_ZIP_URL'！${NC}"
        echo -e "${YELLOW}请先编辑此脚本文件，在顶部填入你的配置文件ZIP包下载地址。${NC}"
        exit 1
    fi
    echo -e "${GREEN}👍 配置文件下载地址已确认。${NC}"
    echo "----------------------------------------------------------------"
}

# 检查架构并设置文件名
get_arch() {
    echo -e "🕵️  正在检测系统架构..."
    ARCH=$(uname -m)
    MIHOMO_ARCH=""

    case $ARCH in
        x86_64)
            MIHOMO_ARCH="amd64-v2"
            ;;
        aarch64)
            MIHOMO_ARCH="arm64-v8"
            ;;
        armv7l)
            MIHOMO_ARCH="armv7"
            ;;
        *)
            echo -e "${RED}❌ 不支持的架构: $ARCH！${NC}"
            echo -e "${YELLOW}脚本目前只支持 x86_64 (amd64-v2), aarch64 (arm64-v8), armv7l (armv7)。${NC}"
            exit 1
            ;;
    esac
    echo -e "${GREEN}✅ 架构确认: $ARCH (对应 Mihomo 版本: $MIHOMO_ARCH)${NC}"
    echo "----------------------------------------------------------------"
}

# 更换系统源
change_apt_sources() {
    if grep -q -E "(aliyun|tuna|ustc)" /etc/apt/sources.list; then
        echo -e "${GREEN}👍 系统源似乎已更换 (检测到 aliyun/tuna/ustc)，跳过此步骤。${NC}"
        echo "----------------------------------------------------------------"
        return
    fi
    
    echo -e "🔧 正在执行换源脚本 (linuxmirrors.cn/main.sh)..."
    bash <(curl -sSL https://linuxmirrors.cn/main.sh)
    echo -e "${GREEN}✅ 换源脚本执行完毕。${NC}"
    echo "----------------------------------------------------------------"
}

# 安装 Docker
install_docker() {
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}👍 Docker 已经安装，跳过此步骤。${NC}"
        echo "----------------------------------------------------------------"
        return
    fi
        
    echo -e "🐳 正在执行 Docker 安装脚本 (linuxmirrors.cn/docker.sh)..."
    bash <(curl -sSL https://linuxmirrors.cn/docker.sh)
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker 安装失败！ 'docker' 命令不可用。${NC}"
        echo -e "${YELLOW}请检查 Docker 安装脚本的输出。${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Docker 安装成功。${NC}"
    echo "----------------------------------------------------------------"
}

# 从 tar 包安装 Sub-Store (幂等检查)
install_substore_from_tar() {
    CONTAINER_NAME="sub-store"
    IMAGE_NAME="xream/sub-store:latest"

    # 1. 检查容器是否正在运行
    if [ $(docker ps -q -f name=^/${CONTAINER_NAME}$) ]; then
        echo -e "${GREEN}👍 Sub-Store 容器 'sub-store' 已经在运行，跳过。${NC}"
        echo "----------------------------------------------------------------"
        return
    fi

    # 2. 检查容器是否存在但已停止
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

    # 3. 容器不存在或启动失败，则创建
    # 检查镜像是否存在
    if ! docker images -q $IMAGE_NAME | grep -q . ; then
        echo -e "${YELLOW}🔎 未找到 '$IMAGE_NAME' 镜像，正在下载...${NC}"
        echo -e "📦 正在下载 Sub-Store Docker 镜像包..."
        wget "https://ghfast.top/github.com/Scu9277/TProxy/releases/download/1.0/sub-store.tar.gz" -O "/root/sub-store.tar.gz"
        
        echo -e "🗜️ 正在解压并加载镜像..."
        tar -xzf "/root/sub-store.tar.gz" -C "/root/"
        docker load -i "/root/sub-store.tar"
        
        echo -e "🧹 正在清理 Sub-Store .tar.gz 和 .tar 文件..."
        rm -f "/root/sub-store.tar.gz" "/root/sub-store.tar"
    else
        echo -e "${GREEN}👍 发现 '$IMAGE_NAME' 镜像，跳过下载。${NC}"
    fi

    # 4. 运行 Docker 容器
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
    
    # 5. 最终检查
    if [ $(docker ps -q -f name=^/${CONTAINER_NAME}$) ]; then
        echo -e "${GREEN}✅ Sub-Store 容器已成功启动 (端口 9277)！${NC}"
    else
        echo -e "${RED}❌ Sub-Store 容器启动失败！${NC}"
        echo -e "${YELLOW}请使用 'docker logs $CONTAINER_NAME' 查看容器日志。${NC}"
    fi
    echo "----------------------------------------------------------------"
}


# 下载并安装 Mihomo (幂等检查)
install_mihomo() {
    if command -v mihomo &> /dev/null; then
        echo -e "${GREEN}👍 Mihomo 已经安装，跳过下载和安装。${NC}"
        mihomo -v
        echo "----------------------------------------------------------------"
        return
    fi
        
    echo -e "📡 正在从 GitHub API 获取最新版本号..."
    API_URL="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
    
    LATEST_TAG=$(curl -sL $API_URL | jq -r .tag_name)

    if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" == "null" ]; then
        echo -e "${RED}❌ 获取最新版本号失败！可能是网络问题或API限制。${NC}"
        exit 1
    fi

    echo -e "${GREEN}🎉 找到最新版本: $LATEST_TAG${NC}"

    DEB_FILENAME="mihomo-linux-${MIHOMO_ARCH}-${LATEST_TAG}.deb"
    DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_TAG}/${DEB_FILENAME}"
    FAST_DOWNLOAD_URL="https://ghfast.top/${DOWNLOAD_URL}"
    DEB_PATH="/root/${DEB_FILENAME}"

    echo -e "🚀 准备从国内加速镜像下载..."
    echo -e "${YELLOW}下载链接: $FAST_DOWNLOAD_URL${NC}"

    wget -O "$DEB_PATH" "$FAST_DOWNLOAD_URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 下载失败！请检查网络或链接。${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ 下载完成！文件保存在: $DEB_PATH${NC}"
    echo -e "📦 正在使用 dpkg 安装..."
    
    dpkg -i "$DEB_PATH"
    echo -e "${GREEN}✅ Mihomo 安装成功！${NC}"

    echo -e "🧹 正在清理下载的 .deb 文件..."
    rm -f "$DEB_PATH"
    
    echo -e "🔍 验证安装..."
    mihomo -v
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}👍 Mihomo 已成功运行并验证！${NC}"
    else
        echo -e "${RED}❌ Mihomo 验证失败！${NC}"
        exit 1
    fi
    echo "----------------------------------------------------------------"
}

# 下载并配置 (增加覆盖确认)
setup_config() {
    if [ -f "/etc/mihomo/config.yaml" ]; then
        echo -e "${YELLOW}⚠️  检测到已存在的 Mihomo 配置文件 (/etc/mihomo/config.yaml)。${NC}"
        read -p "是否要从 $CONFIG_ZIP_URL 覆盖它? (y/N): " choice
        case "$choice" in 
          y|Y ) 
            echo -e "🔄 好的，将继续下载并覆盖配置..."
            ;;
          * ) 
            echo -e "👍 保留现有配置，跳过下载。${NC}"
            echo "----------------------------------------------------------------"
            return
            ;;
        esac
    fi
    
    echo -e "📂 正在配置您的 mihomo 配置文件..."
    echo -e "🔗 您的配置文件地址: $CONFIG_ZIP_URL"
    echo -e "📡 正在请求蓝奏云解析 API..."
    
    API_RESOLVE_URL="https://api.zxki.cn/api/lzy?url=${CONFIG_ZIP_URL}"
    REAL_DOWN_URL=$(curl -sL "$API_RESOLVE_URL" | jq -r .downUrl)
    
    if [ -z "$REAL_DOWN_URL" ] || [ "$REAL_DOWN_URL" == "null" ]; then
        echo -e "${RED}❌ 错误：无法从 API 解析到下载地址！${NC}"
        echo -e "${YELLOW}请检查你的 CONFIG_ZIP_URL (蓝奏云链接) 是否正确，或者 API (api.zxki.cn) 是否可用。${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ 成功解析到真实下载地址！${NC}"
    echo -e "🚀 准备下载配置文件..."
    
    CONFIG_ZIP_PATH="/root/mihomo_config.zip"
    TEMP_DIR="/root/mihomo_temp_unzip"

    wget -O "$CONFIG_ZIP_PATH" "$REAL_DOWN_URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 配置文件下载失败！请检查解析后的下载链接是否有效。${NC}"
        exit 1
    fi

    echo -e "🤐 正在解压配置文件..."
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    unzip -o "$CONFIG_ZIP_PATH" -d "$TEMP_DIR"

    if [ -d "$TEMP_DIR/mihomo" ]; then
        echo -e "📁 发现 'mihomo' 文件夹，正在覆盖到 /etc/ ..."
        rm -rf /etc/mihomo
        mv "$TEMP_DIR/mihomo" /etc/
    elif [ -f "$TEMP_DIR/config.yaml" ]; then
        echo -e "📄 发现配置文件，正在覆盖到 /etc/mihomo/ ..."
        mkdir -p /etc/mihomo
        mv "$TEMP_DIR"/* /etc/mihomo/
    else
        echo -e "${RED}❌ 错误：无法识别的 ZIP 压缩包结构！${NC}"
        echo -e "${YELLOW}请确保你的 ZIP 包里包含一个 'mihomo' 文件夹，或者直接包含 'config.yaml' 等配置文件。${NC}"
        rm -f "$CONFIG_ZIP_PATH"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    echo -e "${GREEN}✅ 配置文件部署成功！${NC}"
    echo -e "🧹 正在清理下载的 .zip 和临时文件..."
    rm -f "$CONFIG_ZIP_PATH"
    rm -rf "$TEMP_DIR"
    echo "----------------------------------------------------------------"
}

# 启动 Mihomo 服务
start_mihomo_service() {
    echo -e "🚀 正在启动并设置 mihomo 服务为开机自启..."
    systemctl enable mihomo
    # 无论如何都重启一次
    systemctl restart mihomo
    
    echo -e "⏳ 正在等待服务启动 (3秒)..."
    sleep 3
    
    if systemctl is-active --quiet mihomo; then
        echo -e "${GREEN}✅ Mihomo 服务正在愉快地运行！${NC}"
        systemctl status mihomo --no-pager | head -n 5
    else
        echo -e "${RED}❌ Mihomo 服务启动失败！${NC}"
        echo -e "${YELLOW}请使用 'systemctl status mihomo' 或 'journalctl -u mihomo' 查看详细日志。${NC}"
        exit 1
    fi
    echo "----------------------------------------------------------------"
}

# 🆕 新增：运行您提供的最新 TProxy 脚本
run_tproxy() {
    # 幂等性检查：基于 TProxy 脚本创建的 systemd service 文件
    if [ -f "/etc/systemd/system/tproxy-rules.service" ]; then
        echo -e "${GREEN}👍 TProxy systemd service 已存在，假定 TProxy 已安装，跳过。${NC}"
        echo -e "${YELLOW}如需重新运行 TProxy 脚本，请先手动删除 /etc/systemd/system/tproxy-rules.service 再执行${NC}"
        echo "----------------------------------------------------------------"
        return
    fi

    echo -e "🔧 准备执行 TProxy 脚本 (tproxy_mihomo-1.sh)..."
    echo -e "${YELLOW}TProxy 脚本将接管网络设置，请注意！${NC}"
    
    TPROXY_SCRIPT_URL="https://ghfast.top/https://raw.githubusercontent.com/Scu9277/TProxy/refs/heads/main/tproxy_mihomo-1.sh"
    
    # 执行 TProxy 脚本
    bash <(curl -sSL "$TPROXY_SCRIPT_URL")
    
    echo -e "${GREEN}✅ TProxy 脚本执行完毕！${NC}"
    echo -e "${YELLOW}ℹ️ 脚本已信任 tproxy_mihomo-1.sh 会自动处理 9277 端口豁免和规则持久化。${NC}"
    echo "----------------------------------------------------------------"
}


# --- 主函数 ---
main() {
    show_author_info
    check_root
    
    # 第 1 步：更新源
    echo -e "🔄 ${YELLOW}第 1 步：更新系统源...${NC}"
    apt-get update -y
    echo "----------------------------------------------------------------"

    # 第 2 步：安装依赖
    echo -e "🛠️ ${YELLOW}第 2 步：安装基础依赖...${NC}"
    check_dependencies
    
    # 第 3 步：执行换源脚本
    echo -e "🌐 ${YELLOW}第 3 步：更换系统镜像源...${NC}"
    change_apt_sources
    
    # 第 4 步：安装 Docker
    echo -e "🐳 ${YELLOW}第 4 步：安装 Docker...${NC}"
    install_docker
    
    # 第 5 步：运行 Sub-Store 容器
    echo -e "🏪 ${YELLOW}第 5 步：安装并启动 Sub-Store...${NC}"
    install_substore_from_tar
    
    # 第 6 步：安装 Mihomo
    echo -e "🚀 ${YELLOW}第 6 步：安装 Mihomo...${NC}"
    check_config_url # 检查配置链接
    get_arch         # 检查架构
    install_mihomo   # 安装 Mihomo (带检查)
    setup_config     # 部署配置 (带检查)
    start_mihomo_service # 启动 Mihomo (总是重启)

    # 第 7 步：安装 TProxy
    echo -e "🛡️ ${YELLOW}第 7 步：安装 TProxy...${NC}"
    run_tproxy

    # 获取局域网IP
    echo -e "📡 正在获取本机局域网 IP..."
    LAN_IP=$(hostname -I | awk '{print $1}')
    if [ -z "$LAN_IP" ]; then
        echo -e "${YELLOW}⚠️ 未能自动获取局域网 IP。请手动查询。${NC}"
        LAN_IP="<你的局域网IP>"
    else
        echo -e "${GREEN}✅ 本机 IP: $LAN_IP${NC}"
    fi


    # 最终输出打印到控制台并保存到日志文件
    (
    echo "================================================================"
    echo -e "🎉 ${GREEN}哇哦！全部搞定！${NC} 🎉"
    echo ""
    echo -e "Mihomo 和 TProxy 应该已经完美运行起来了！"
    echo -e "Sub-Store Docker 容器也已启动！(TProxy豁免已生效)"
    echo ""
    echo -e "--- ${BLUE}Mihomo (仪表盘) ${NC}---"
    echo -e "Mihomo UI: ${YELLOW}http://${LAN_IP}/ui${NC}"
    echo -e "主机名: ${YELLOW}${LAN_IP}${NC}"
    echo -e "端口: ${YELLOW}80${NC}"
    echo -e "密码: ${YELLOW}1381ni${NC}"
    echo ""
    echo -e "--- ${BLUE}Sub-Store (订阅管理) ${NC}---"
    echo -e "Sub-Store UI: ${YELLOW}http://${LAN_IP}:9277/${NC}"
    echo -e "后端API Path: ${YELLOW}/21DEDINGZHI${NC}"
    echo ""
    echo -e "--- ${BLUE}联系作者 ${NC}---"
    echo -e "📧 邮箱: ${YELLOW}shangkouyou@gmail.com${NC}"
    echo -e "💬 微信: ${YELLOW}shangkouyou${NC}"
    echo ""
    echo -e "享受你的网络吧！🥳 ${RED}有需要调整服务的可以联系👆微信或者是邮件咨询✨${NC}"
    echo ""
    echo -e "再次感谢使用私人订制服务！ - ${GREEN}Scu x Duang${NC}"
    echo "================================================================"
    ) | tee /root/ScuDEDINGZHI.txt
}

# 启动！
main
