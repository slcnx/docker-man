#!/bin/bash
# 构建 Docker Man 基础镜像

set -e

# 颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== 构建 Docker Man 基础镜像 ===${NC}"
echo ""

# 构建基础镜像
echo -e "${GREEN}正在构建 docker-man-base:latest ...${NC}"
docker build -f base.dockerfile -t docker-man-base:latest .

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ 基础镜像构建成功！${NC}"
    echo ""
    echo -e "${YELLOW}镜像信息：${NC}"
    docker images docker-man-base
else
    echo -e "${YELLOW}✗ 基础镜像构建失败${NC}"
    exit 1
fi
