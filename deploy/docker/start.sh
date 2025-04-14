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
log_info "Alpine版本: $(cat /etc/alpine-release)"
log_info "可用内存: $(free -m | grep Mem | awk '{print $2}') MB"
log_info "可用磁盘空间: $(df -h / | tail -1 | awk '{print $4}')"

# 启动服务器
log_success "所有检查通过，正在启动服务器..."
cd /app
exec /app/bin/attack-server -config /app/backend/config.json 