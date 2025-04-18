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
    
    # 确保go.sum文件存在
    touch backend/go.sum
    touch go.sum
    
    # 先检查是否有gorilla/mux依赖，没有就添加
    if ! grep -q "github.com/gorilla/mux" backend/go.mod; then
        info "添加缺失的gorilla/mux依赖到go.mod..."
        echo "require github.com/gorilla/mux v1.8.0" >> backend/go.mod
    fi
    
    # 修复未使用的导入
    if grep -q "path/filepath" backend/middleware/auth.go && ! grep -q "filepath\." backend/middleware/auth.go; then
        info "修复auth.go中未使用的filepath导入..."
        sed -i '/path\/filepath/d' backend/middleware/auth.go
    fi
    
    if command -v go &> /dev/null; then
        # 使用本地Go安装预处理依赖
        (cd backend && go mod tidy && go mod download) || warn "本地预处理Go依赖失败，将在Docker中尝试"
    else
        warn "未检测到本地Go安装，将在Docker中处理依赖"
    fi
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

# 确保部署脚本目录存在
mkdir -p deploy/docker

# 确保启动脚本存在
info "检查启动脚本..."
if [ ! -f "deploy/docker/start.sh" ]; then
    info "创建启动脚本文件..."
    mkdir -p deploy/docker
    cat > deploy/docker/start.sh << 'EOFMARKER'
#!/bin/sh

# 函数定义
log_info() {
  echo "[INFO] $1"
}

log_warn() {
  echo "[WARN] $1"
}

log_error() {
  echo "[ERROR] $1"
}

log_success() {
  echo "[SUCCESS] $1"
}

# 设置错误处理
set -e

# 处理信号，实现优雅关闭
trap_handler() {
  log_info "接收到关闭信号，正在停止服务..."
  # 这里可以添加清理操作
  exit 0
}

# 注册信号处理器
trap 'trap_handler' INT TERM

# 显示容器信息
log_info "===================================="
log_info "    GOSYNFLOOD管理平台启动中..."
log_info "===================================="
log_info "版本: 1.0.0"
log_info "启动时间: $(date)"
log_info "服务端口: 31457"

# 更新管理员令牌
if [ ! -z "$ADMIN_TOKEN" ]; then
  sed -i "s/AdminToken = \".*\"/AdminToken = \"$ADMIN_TOKEN\"/g" /app/backend/middleware/auth.go
  log_success "管理员令牌已更新"
else
  log_warn "未设置ADMIN_TOKEN环境变量，使用默认令牌"
fi

# 系统检查
log_info "执行系统检查..."

# 目录检查
for dir in "/app/bin" "/app/backend" "/app/backend/static" "/app/data"; do
  if [ ! -d "$dir" ]; then
    log_error "错误: 目录不存在: $dir"
    mkdir -p "$dir"
    log_info "已自动创建目录: $dir"
  fi
done

# 文件检查
if [ ! -f "/app/bin/attack-server" ]; then
  log_error "错误: 找不到服务器二进制文件: /app/bin/attack-server"
  log_error "请检查构建过程是否正确完成"
  exit 1
fi

if [ ! -f "/app/backend/config.json" ]; then
  log_error "错误: 找不到配置文件: /app/backend/config.json"
  cat > /app/backend/config.json << EOF
{
  "host": "0.0.0.0",
  "port": 31457,
  "staticDir": "./static",
  "logLevel": "info",
  "allowedOrigins": "*",
  "dataDir": "../data"
}
EOF
  log_info "已创建默认配置文件: /app/backend/config.json"
fi

if [ ! -f "/app/backend/middleware/auth.go" ]; then
  log_error "错误: 找不到认证中间件: /app/backend/middleware/auth.go"
  log_error "将尝试创建默认认证中间件"
  
  mkdir -p /app/backend/middleware
  cat > /app/backend/middleware/auth.go << EOF
package middleware

import (
	"net/http"
)

var (
    AdminToken = "change-me-to-secure-token" 
)

// AdminAuthMiddleware 验证管理员令牌
func AdminAuthMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := r.Header.Get("X-Admin-Token")
		if token != AdminToken {
			http.Error(w, "未授权访问", http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}
EOF
  log_info "已创建默认认证中间件"
fi

# 验证静态文件目录
if [ -z "$(ls -A /app/backend/static 2>/dev/null)" ]; then
  log_warn "警告: 静态文件目录为空，前端可能无法正常工作"
  mkdir -p /app/backend/static
  echo "<html><body><h1>GOSYNFLOOD管理平台</h1><p>警告: 前端文件缺失，请检查构建过程。</p></body></html>" > /app/backend/static/index.html
  log_info "已创建临时前端页面"
fi

# 验证数据目录权限
if [ ! -w "/app/data" ]; then
  log_error "错误: 数据目录没有写入权限: /app/data"
  chmod 755 /app/data
  log_info "已尝试修复数据目录权限"
fi

# 记录环境信息
log_info "系统检查完成"
log_info "环境信息:"
log_info "Alpine版本: $(cat /etc/alpine-release 2>/dev/null || echo '未知')"
log_info "可用内存: $(free -m 2>/dev/null | grep Mem | awk '{print $2}' 2>/dev/null || echo '未知') MB"
log_info "可用磁盘空间: $(df -h / 2>/dev/null | tail -1 | awk '{print $4}' 2>/dev/null || echo '未知')"

# 启动服务器
log_success "所有检查通过，正在启动服务器..."
cd /app
exec /app/bin/attack-server -config /app/backend/config.json
EOFMARKER
    chmod +x deploy/docker/start.sh
    info "启动脚本已创建并设置执行权限"
fi

# 确保backend/static目录存在
mkdir -p backend/static

# 检查docker-compose.yml中的端口配置
info "检查docker-compose.yml中的端口配置..."
if grep -q "31458:31457" docker-compose.yml; then
    info "使用更新的端口映射: 31458:31457"
    PORT_INFO="31458"
elif grep -q "31457:31457" docker-compose.yml; then
    info "使用默认端口映射: 31457:31457"
    PORT_INFO="31457"
else
    warn "无法确定端口映射，假设使用31457"
    PORT_INFO="31457"
fi

# 检查端口是否被占用
info "检查端口占用情况..."
if command -v netstat &> /dev/null; then
    if netstat -tuln | grep -q ":$PORT_INFO "; then
        warn "端口 $PORT_INFO 已被占用，将尝试使用备用端口31459"
        PORT_INFO="31459"
        sed -i "s/$PORT_INFO:31457/31459:31457/g" docker-compose.yml || warn "无法自动更新端口，请手动编辑docker-compose.yml文件"
    fi
elif command -v ss &> /dev/null; then
    if ss -tuln | grep -q ":$PORT_INFO "; then
        warn "端口 $PORT_INFO 已被占用，将尝试使用备用端口31459"
        PORT_INFO="31459"
        sed -i "s/$PORT_INFO:31457/31459:31457/g" docker-compose.yml || warn "无法自动更新端口，请手动编辑docker-compose.yml文件"
    fi
else
    warn "找不到netstat或ss命令，无法检查端口占用情况"
fi

# 在构建前检查前端文件
if [ -f "deploy/docker/debug-tools.sh" ]; then
  info "检查前端构建环境..."
  chmod +x deploy/docker/debug-tools.sh
  ./deploy/docker/debug-tools.sh inspect

  # 检测前端构建状态
  if [ ! -d "backend/static" ] || [ -z "$(ls -A backend/static 2>/dev/null)" ]; then
    warn "检测到前端文件可能有问题，尝试修复..."
    ./deploy/docker/debug-tools.sh fix
  fi
fi

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
    success "管理平台地址: http://localhost:$PORT_INFO"
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

# 验证令牌设置
info "验证认证令牌设置..."
sleep 3 # 等待容器完全启动
TOKEN_VALUE=$(docker exec gosynflood-manager grep -o 'AdminToken = "[^"]*"' /app/backend/middleware/auth.go 2>/dev/null)
if [[ "$TOKEN_VALUE" == *"$ADMIN_TOKEN"* ]]; then
    success "认证令牌已正确设置: $TOKEN_VALUE"
else
    warn "认证令牌可能未正确设置。实际值: $TOKEN_VALUE"
    warn "如果登录失败，请使用以下命令修复令牌:"
    echo "docker exec gosynflood-manager sh -c \"echo 'package middleware

import (
    \\\"encoding/json\\\"
    \\\"io\\\"
    \\\"net/http\\\"
    \\\"strings\\\"
    \\\"time\\\"
    \\\"path/filepath\\\"
    \\\"os\\\"
)

// 配置保存在内存中的安全令牌
var (
    AdminToken = \\\"$ADMIN_TOKEN\\\" // 生产环境应使用环境变量
)' > /tmp/header.txt && sed -n '/func AdminAuthMiddleware/,\\\$p' /app/backend/middleware/auth.go > /tmp/body.txt && cat /tmp/header.txt /tmp/body.txt > /app/backend/middleware/auth.go\""
    echo "docker restart gosynflood-manager"
fi

echo "" 