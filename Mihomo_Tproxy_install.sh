#!/bin/bash

#=================================================================================
#   _  _ ___   _   _ ___ ___ ___  ___ 
#  | \| | __| /_\ | | _ \ __/ __|/ __|
#  | .` | _| / _ \| |  _/ _|\__ \ (__ 
#  |_|\_|___/_/ \_\_|_| |___|___/\___|
#
#   Mihomo (MetaCubeX) 全自动安装 & TProxy 配置脚本
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
# 最佳实践: 
# 1. 把你的 mihomo 文件夹 (包含 config.yaml, Country.mmdb 等)
# 2. 把这个文件夹压缩成 mihomo.zip
# 3. 上传到蓝奏云，获取分享链接 (不要带密码)
# 4. 把分享链接填在下面
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
    echo "     Mihomo (MetaCubeX) 全自动安装 & TProxy 配置脚本"
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
    echo -e "🔍 正在检查系统依赖 (wget, curl, jq, unzip)..."
    DEPS=("wget" "curl" "jq" "unzip")
    MISSING_DEPS=()

    for dep in "${DEPS[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            MISSING_DEPS+=("$dep")
        fi
    done

    if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
        echo -e "${YELLOW}🔧 检测到缺失的依赖: ${MISSING_DEPS[*]} ... 正在尝试自动安装...${NC}"
        # 更新apt缓存
        apt-get update -y
        # 安装缺失的依赖
        apt-get install -y "${MISSING_DEPS[@]}"
        
        # 再次检查
        for dep in "${MISSING_DEPS[@]}"; do
            if ! command -v "$dep" &> /dev/null; then
                echo -e "${RED}❌ 依赖 $dep 安装失败！请手动安装后再试。${NC}"
                exit 1
            fi
        done
        echo -e "${GREEN}✅ 所有依赖已安装完毕！${NC}"
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

# 下载并安装 Mihomo
install_mihomo() {
    echo -e "📡 正在从 GitHub API 获取最新版本号..."
    API_URL="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
    
    # 使用 curl 获取，并通过 jq 解析 tag_name
    LATEST_TAG=$(curl -sL $API_URL | jq -r .tag_name)

    if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" == "null" ]; then
        echo -e "${RED}❌ 获取最新版本号失败！可能是网络问题或API限制。${NC}"
        exit 1
    fi

    echo -e "${GREEN}🎉 找到最新版本: $LATEST_TAG${NC}"

    # 构造文件名和下载链接
    DEB_FILENAME="mihomo-linux-${MIHOMO_ARCH}-${LATEST_TAG}.deb"
    DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_TAG}/${DEB_FILENAME}"
    FAST_DOWNLOAD_URL="https://ghfast.top/${DOWNLOAD_URL}"
    DEB_PATH="/root/${DEB_FILENAME}"

    echo -e "🚀 准备从国内加速镜像下载..."
    echo -e "${YELLOW}下载链接: $FAST_DOWNLOAD_URL${NC}"

    # 使用 wget 下载到 /root/
    wget -O "$DEB_PATH" "$FAST_DOWNLOAD_URL"

    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 下载失败！请检查网络或链接。${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ 下载完成！文件保存在: $DEB_PATH${NC}"
    echo -e "📦 正在使用 dpkg 安装..."

    # 安装 .deb 包
    dpkg -i "$DEB_PATH"
    echo -e "${GREEN}✅ Mihomo 安装成功！${NC}"

    echo -e "🧹 正在清理下载的 .deb 文件..."
    rm -f "$DEB_PATH"
    
    echo -e "🔍 验证安装..."
    # 运行 mihomo -v 检查是否能正常执行
    mihomo -v
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}👍 Mihomo 已成功运行并验证！${NC}"
    else
        echo -e "${RED}❌ Mihomo 验证失败！${NC}"
        exit 1
    fi
    echo "----------------------------------------------------------------"
}

# 下载并配置
setup_config() {
    echo -e "📂 正在配置您的 mihomo 配置文件..."
    echo -e "🔗 您的配置文件地址: $CONFIG_ZIP_URL"
    echo -e "📡 正在请求蓝奏云解析 API..."
    
    API_RESOLVE_URL="https://api.zxki.cn/api/lzy?url=${CONFIG_ZIP_URL}"
    
    # 使用 curl 和 jq 解析 JSON
    # curl -sL: 静默模式并跟随跳转
    # jq -r .downUrl: -r 表示输出原始字符串 (不带引号)
    REAL_DOWN_URL=$(curl -sL "$API_RESOLVE_URL" | jq -r .downUrl)
    
    if [ -z "$REAL_DOWN_URL" ] || [ "$REAL_DOWN_URL" == "null" ]; then
        echo -e "${RED}❌ 错误：无法从 API 解析到下载地址！${NC}"
        echo -e "${YELLOW}请检查你的 CONFIG_ZIP_URL (蓝奏云链接) 是否正确，或者 API (api.zxki.cn) 是否可用。${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ 成功解析到真实下载地址！${NC}"
    echo -e "🚀 准备下载配置文件..."
    # echo -e "${YELLOW}下载链接: $REAL_DOWN_URL${NC}" # 链接太长，不完全显示
    
    CONFIG_ZIP_PATH="/root/mihomo_config.zip"
    TEMP_DIR="/root/mihomo_temp_unzip"

    # 下载配置文件 (使用解析后的真实地址)
    wget -O "$CONFIG_ZIP_PATH" "$REAL_DOWN_URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 配置文件下载失败！请检查解析后的下载链接是否有效。${NC}"
        exit 1
    fi

    echo -e "🤐 正在解压配置文件..."
    # 清理旧的临时目录
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    # 解压
    unzip -o "$CONFIG_ZIP_PATH" -d "$TEMP_DIR"

    # 检查解压后的结构
    # 场景1: ZIP包里直接是一个 'mihomo' 文件夹 (如你所述)
    if [ -d "$TEMP_DIR/mihomo" ]; then
        echo -e "📁 发现 'mihomo' 文件夹，正在覆盖到 /etc/ ..."
        # 删掉旧的配置
        rm -rf /etc/mihomo
        # 移动新的
        mv "$TEMP_DIR/mihomo" /etc/
    # 场景2: ZIP包里是 config.yaml, Country.mmdb 等文件
    elif [ -f "$TEMP_DIR/config.yaml" ]; then
        echo -e "📄 发现配置文件，正在覆盖到 /etc/mihomo/ ..."
        mkdir -p /etc/mihomo
        # 移动所有文件
        mv "$TEMP_DIR"/* /etc/mihomo/
    else
        echo -e "${RED}❌ 错误：无法识别的 ZIP 压缩包结构！${NC}"
        echo -e "${YELLOW}请确保你的 ZIP 包里包含一个 'mihomo' 文件夹，或者直接包含 'config.yaml' 等配置文件。${NC}"
        # 清理
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

# 启动服务
start_services() {
    echo -e "🚀 正在启动并设置 mihomo 服务为开机自启..."
    
    # 启用服务
    systemctl enable mihomo
    
    # 重启服务
    systemctl restart mihomo
    
    echo -e "⏳ 正在等待服务启动 (3秒)..."
    sleep 3
    
    # 检查服务状态
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

# 运行 TProxy 脚本
run_tproxy() {
    echo -e "🔧 准备执行 TProxy 脚本..."
    echo -e "${YELLOW}TProxy 脚本将接管网络设置，请注意！${NC}"
    
    TPROXY_SCRIPT_URL="https://ghfast.top/https://raw.githubusercontent.com/Scu9277/TProxy/refs/heads/main/tproxy.sh"
    
    # 执行 TProxy 脚本
    bash <(curl -sSL "$TPROXY_SCRIPT_URL")
    
    echo -e "${GREEN}✅ TProxy 脚本执行完毕！${NC}"
}

# --- 主函数 ---
main() {
    show_author_info
    check_root
    check_dependencies
    check_config_url
    get_arch
    install_mihomo
    setup_config
    start_services
    run_tproxy

    echo "================================================================"
    echo -e "🎉 ${GREEN}哇哦！全部搞定！${NC} 🎉"
    echo ""
    echo -e "Mihomo 和 TProxy 应该已经完美运行起来了！"
    echo -e "享受你的网络吧！ 🥳"
    echo ""
    echo -e "再次感谢使用！ - ${GREEN}Scu 联合x Duang${NC}"
    echo -e "📧 邮箱: ${YELLOW}shangkouyou@gmail.com${NC}"
    echo -e "💬 微信: ${YELLOW}shangkouyou${NC}"
    echo "================================================================"
}

# 启动！
main



