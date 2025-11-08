#!/bin/bash
# =========================================================
#  Sub-Store Docker 独立安装脚本
# ---------------------------------------------------------
#  作者: shangkouyou
#  版本: v1.0
#  日期: 2025-11-09
#  说明:
#    本脚本用于独立部署并运行 Sub-Store 容器，
#    支持自动检测、下载镜像、启动与数据持久化。
# ---------------------------------------------------------
#  原始来源: Scu9277/TProxy 项目
#  修改与提取: Scu xDuang
# =========================================================

set -e

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
NC="\033[0m"

install_substore_from_tar() {
  CONTAINER_NAME="sub-store"
  IMAGE_NAME="xream/sub-store:latest"

  echo -e "\n${GREEN}==== Sub-Store 安装启动过程开始 ====${NC}"

  # 1️⃣ 检查容器是否运行
  if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo -e "${GREEN}✅ 容器 '${CONTAINER_NAME}' 已在运行，跳过安装。${NC}"
    return
  fi

  # 2️⃣ 检查容器是否存在但已停止
  if [ "$(docker ps -a -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo -e "${YELLOW}⚙️ 发现已停止的 '${CONTAINER_NAME}' 容器，尝试启动...${NC}"
    docker start "$CONTAINER_NAME"
    sleep 3
    if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
      echo -e "${GREEN}✅ Sub-Store 容器启动成功！${NC}"
      return
    else
      echo -e "${RED}❌ 启动失败，移除旧容器并重新创建...${NC}"
      docker rm "$CONTAINER_NAME"
    fi
  fi

  # 3️⃣ 如果镜像不存在，自动下载
  if ! docker images -q "$IMAGE_NAME" | grep -q .; then
    echo -e "${YELLOW}🔄 未检测到镜像 '$IMAGE_NAME'，开始下载...${NC}"
    wget -q "https://ghfast.top/github.com/Scu9277/TProxy/releases/download/1.0/sub-store.tar.gz" -O "/root/sub-store.tar.gz"
    echo -e "${YELLOW}📦 解压并加载镜像...${NC}"
    tar -xzf "/root/sub-store.tar.gz" -C "/root/"
    docker load -i "/root/sub-store.tar"
    echo -e "${YELLOW}🧹 清理安装包...${NC}"
    rm -f "/root/sub-store.tar.gz" "/root/sub-store.tar"
  else
    echo -e "${GREEN}✅ 检测到镜像 '$IMAGE_NAME'，跳过下载。${NC}"
  fi

  # 4️⃣ 运行容器
  echo -e "${YELLOW}🚀 启动 Sub-Store 容器中...${NC}"
  docker run -it -d --restart=always \
    -e "SUB_STORE_BACKEND_SYNC_CRON=55 23 * * *" \
    -e "SUB_STORE_FRONTEND_BACKEND_PATH=/21DEDINGZHI" \
    -p 0.0.0.0:9277:3001 \
    -v /root/sub-store-data:/opt/app/data \
    --name "$CONTAINER_NAME" \
    "$IMAGE_NAME"

  echo -e "⏳ 等待容器初始化中..."
  sleep 5

  # 5️⃣ 检查容器运行状态
  if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo -e "${GREEN}🎉 Sub-Store 容器已成功运行！${NC}"
    echo -e "🌐 访问地址: http://<服务器IP>:9277"
  else
    echo -e "${RED}❌ Sub-Store 容器启动失败！${NC}"
    echo -e "${YELLOW}请运行: docker logs $CONTAINER_NAME 查看日志。${NC}"
    exit 1
  fi

  echo -e "${GREEN}==== Sub-Store 安装启动过程完成 ====${NC}\n"
}

# ---- 主程序 ----
if ! command -v docker &> /dev/null; then
  echo -e "${RED}❌ 未检测到 Docker，请先安装 Docker 再执行此脚本。${NC}"
  exit 1
fi

install_substore_from_tar
