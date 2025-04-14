#!/bin/bash

# Docker部署脚本 - 用于构建和部署gosynflood-union管理平台
# 使用方法: ./deploy/docker-deploy.sh [--token YOUR_TOKEN]

# 显示彩色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 输出函数
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 检查是否存在docker
if ! command -v docker &> /dev/null; then
    error "Docker未安装，请先安装Docker"
    exit 1
fi

# 检查是否存在docker-compose
if ! command -v docker-compose &> /dev/null; then
    error "Docker Compose未安装，请先安装Docker Compose"
    exit 1
fi

# 默认管理员令牌
ADMIN_TOKEN=$(openssl rand -hex 16)

# 处理命令行参数
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --token)
            ADMIN_TOKEN="$2"
            shift 2
            ;;
        *)
            error "未知参数: $1"
            exit 1
            ;;
    esac
done

# 显示基本信息
info "开始部署gosynflood-union管理平台..."
info "管理员令牌: $ADMIN_TOKEN"

# 清理旧的构建缓存
info "清理Docker构建缓存..."
docker builder prune -f &> /dev/null

# 尝试停止并移除旧容器（如果存在）
info "移除旧容器（如果存在）..."
docker-compose down &> /dev/null

# 检查项目文件
if [ ! -f "docker-compose.yml" ] || [ ! -f "Dockerfile" ]; then
    error "缺少必要的配置文件。请确保当前目录包含docker-compose.yml和Dockerfile文件"
    exit 1
fi

# 确保frontend目录存在并且有正确的权限
if [ -d "frontend" ]; then
    info "设置frontend目录权限..."
    chmod -R 755 frontend/
else
    error "找不到frontend目录，请确保项目结构完整"
    exit 1
fi

# 预处理Go依赖
if [ -f "backend/go.mod" ]; then
    info "预处理Go模块依赖..."
    if command -v go &> /dev/null; then
        # 使用本地Go安装预处理依赖
        (cd backend && go mod tidy && go mod download github.com/gorilla/mux && go mod download) || warn "本地预处理Go依赖失败，将在Docker中尝试"
    else
        warn "未检测到本地Go安装，将在Docker中处理依赖"
    fi
    
    # 确保go.sum文件存在
    touch backend/go.sum
    touch go.sum
fi

# 检查backend/config.json是否存在
if [ ! -f "backend/config.json" ]; then
    warn "找不到backend/config.json，将创建默认配置..."
    mkdir -p backend
    echo '{
  "host": "0.0.0.0",
  "port": 31457,
  "staticDir": "./static",
  "logLevel": "info",
  "allowedOrigins": "*",
  "dataDir": "../data"
}' > backend/config.json
fi

# 确保backend/static目录存在
mkdir -p backend/static

# 开始构建
info "开始构建Docker镜像（这可能需要几分钟）..."
ADMIN_TOKEN=$ADMIN_TOKEN docker-compose build --no-cache

# 检查构建结果
if [ $? -ne 0 ]; then
    error "构建失败，请检查错误信息"
    
    # 尝试修复常见问题
    if grep -q "missing go.sum entry" <<< "$(docker-compose logs 2>&1)"; then
        warn "检测到Go依赖问题，尝试修复..."
        if command -v go &> /dev/null; then
            info "运行: cd backend && go mod download github.com/gorilla/mux && go mod tidy"
            (cd backend && go mod download github.com/gorilla/mux && go mod tidy)
            info "重新尝试构建..."
            ADMIN_TOKEN=$ADMIN_TOKEN docker-compose build --no-cache
            if [ $? -ne 0 ]; then
                error "自动修复失败，请手动修复Go依赖问题"
                exit 1
            fi
        else
            error "修复Go依赖问题需要本地安装Go，请手动安装并运行: cd backend && go mod download github.com/gorilla/mux && go mod tidy"
            exit 1
        fi
    elif grep -q "no such file or directory" <<< "$(docker-compose logs 2>&1)"; then
        warn "检测到文件路径问题，可能是前端构建产物路径不正确"
        info "尝试查看Vue配置..."
        cat frontend/vue.config.js | grep outputDir || echo "未找到outputDir配置"
        
        warn "请检查Dockerfile中COPY命令的路径是否与Vue配置匹配"
    fi
    
    exit 1
fi

# 启动容器
info "构建成功，正在启动容器..."
ADMIN_TOKEN=$ADMIN_TOKEN docker-compose up -d

# 检查启动结果
if [ $? -ne 0 ]; then
    error "启动失败，请检查错误信息"
    exit 1
fi

# 等待几秒钟让容器完全启动
sleep 5

# 检查容器状态
CONTAINER_STATUS=$(docker ps -f "name=gosynflood-manager" --format "{{.Status}}")
if [[ $CONTAINER_STATUS == *"Up"* ]]; then
    success "容器已成功启动！"
    success "管理平台地址: http://localhost:31457"
    success "管理员令牌: $ADMIN_TOKEN"
    
    # 查看日志中的令牌确认
    TOKEN_CONFIRM=$(docker logs gosynflood-manager 2>&1 | grep "管理员令牌已更新")
    if [ -n "$TOKEN_CONFIRM" ]; then
        success "令牌已成功应用到系统"
    else
        warn "未检测到令牌确认信息，请确认系统是否正常运行"
    fi
else
    error "容器可能未正确启动，请使用'docker logs gosynflood-manager'检查详细日志"
fi

# 提供常用命令提示
echo ""
info "以下是一些有用的命令:"
echo "查看容器日志: docker logs gosynflood-manager"
echo "停止服务: docker-compose down"
echo "重启服务: docker-compose restart"
echo "重建镜像: docker-compose build --no-cache && docker-compose up -d"
echo "" 