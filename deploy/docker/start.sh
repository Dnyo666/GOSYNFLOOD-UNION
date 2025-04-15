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

# 检查并分析config.json中的staticDir配置
if [ -f "/app/backend/config.json" ]; then
  log_info "分析配置文件中的静态文件目录配置..."
  STATIC_DIR=$(grep -o '"staticDir"[^,}]*' /app/backend/config.json | cut -d '"' -f 4)
  log_info "配置的静态文件目录: $STATIC_DIR"
  
  # 检查是否为相对路径，并创建软链接确保正确映射
  if [ "${STATIC_DIR:0:1}" = "." ]; then
    # 相对路径处理
    REAL_STATIC_DIR="/app/backend/$STATIC_DIR"
    log_info "检测到相对路径，推测实际静态文件目录: $REAL_STATIC_DIR"
    
    # 确保静态文件目录存在
    mkdir -p "$(dirname "$REAL_STATIC_DIR")"
    
    # 创建到/app/backend/static的软链接
    if [ "$REAL_STATIC_DIR" != "/app/backend/static" ] && [ ! -e "$REAL_STATIC_DIR" ]; then
      ln -sf /app/backend/static "$REAL_STATIC_DIR"
      log_info "创建软链接: /app/backend/static -> $REAL_STATIC_DIR"
    fi
  fi
else
  log_warn "无法解析配置文件中的staticDir，使用默认值"
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

# 前端静态文件检查
log_info "检查前端静态文件..."
static_files_count=$(find /app/backend/static -type f 2>/dev/null | wc -l)
log_info "静态文件数量: $static_files_count"

# 检查是否存在index.html
if [ ! -f "/app/backend/static/index.html" ]; then
  log_warn "警告: 找不到/app/backend/static/index.html文件"
  
  # 检查是否有其他地方的index.html可以复制
  INDEX_PATHS="/app/frontend/dist/index.html /app/frontend/public/index.html"
  for path in $INDEX_PATHS; do
    if [ -f "$path" ]; then
      log_info "找到替代的index.html文件: $path"
      mkdir -p /app/backend/static
      cp -r "$(dirname "$path")/"* /app/backend/static/
      log_info "已复制文件到/app/backend/static/"
      break
    fi
  done
fi

# 如果仍然没有任何静态文件，创建临时页面
if [ "$static_files_count" = "0" ]; then
  log_warn "警告: 静态文件目录为空，前端可能无法正常工作"
  
  # 创建基本的前端文件
  mkdir -p /app/backend/static
  
  cat > /app/backend/static/index.html << EOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>GOSYNFLOOD管理平台</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; padding: 0; background: #f4f4f4; color: #333; }
    .container { max-width: 800px; margin: 50px auto; padding: 20px; background: white; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
    h1 { color: #d9534f; }
    .warning { background: #fcf8e3; border-left: 4px solid #f0ad4e; padding: 10px; margin: 15px 0; }
    .error { background: #f2dede; border-left: 4px solid #d9534f; padding: 10px; margin: 15px 0; }
    .info { background: #d9edf7; border-left: 4px solid #5bc0de; padding: 10px; margin: 15px 0; }
    pre { background: #f8f8f8; padding: 10px; border-radius: 3px; overflow-x: auto; }
    .btn { display: inline-block; padding: 6px 12px; margin-bottom: 0; font-size: 14px; font-weight: 400; text-align: center; white-space: nowrap; vertical-align: middle; cursor: pointer; background-image: none; border: 1px solid transparent; border-radius: 4px; color: #fff; background-color: #5bc0de; border-color: #46b8da; text-decoration: none; }
    .btn:hover { background-color: #31b0d5; border-color: #269abc; }
  </style>
</head>
<body>
  <div class="container">
    <h1>GOSYNFLOOD管理平台</h1>
    <div class="warning">
      <strong>警告:</strong> 前端文件未能正确构建或复制到容器中。这是一个临时页面。
    </div>
    <div class="info">
      <p><strong>系统信息:</strong></p>
      <ul>
        <li>服务器状态: <span style="color:green">正在运行</span></li>
        <li>API状态: 应该可以正常访问</li>
        <li>端口: 31457</li>
        <li>配置文件路径: /app/backend/config.json</li>
        <li>静态文件路径: /app/backend/static</li>
      </ul>
    </div>
    <div class="info">
      <p><strong>调试信息:</strong></p>
      <pre id="debug-info">
容器启动时间: $(date)
配置的静态目录: ${STATIC_DIR:-"./static"} (相对于/app/backend)
静态文件数量: $static_files_count
      </pre>
    </div>
    <p>您可以访问 <a href="/debug.html" class="btn">调试页面</a> 获取更多信息。</p>
  </div>
</body>
</html>
EOF
  log_info "已创建临时前端页面"

  # 创建调试端点
  cat > /app/backend/static/debug.html << EOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>调试信息 - GOSYNFLOOD管理平台</title>
  <style>
    body { font-family: Arial, sans-serif; padding: 20px; margin: 0; line-height: 1.6; }
    h1 { color: #333; }
    .debug-section { margin-bottom: 20px; border: 1px solid #ddd; padding: 15px; border-radius: 4px; }
    h2 { margin-top: 0; color: #31708f; border-bottom: 1px solid #eee; padding-bottom: 10px; }
    pre { background: #f5f5f5; padding: 15px; overflow-x: auto; border-radius: 4px; margin: 0; }
    .btn { display: inline-block; padding: 6px 12px; margin-bottom: 0; font-size: 14px; font-weight: 400; text-align: center; white-space: nowrap; vertical-align: middle; cursor: pointer; background-image: none; border: 1px solid transparent; border-radius: 4px; color: #fff; background-color: #5bc0de; border-color: #46b8da; text-decoration: none; }
    .btn:hover { background-color: #31b0d5; border-color: #269abc; }
    .back-link { margin-bottom: 20px; }
  </style>
</head>
<body>
  <div class="back-link">
    <a href="/" class="btn">返回首页</a>
  </div>
  
  <h1>GOSYNFLOOD管理平台 - 调试信息</h1>
  
  <div class="debug-section">
    <h2>容器目录结构</h2>
    <pre>$(ls -la /app)</pre>
    <h3>Backend目录</h3>
    <pre>$(ls -la /app/backend)</pre>
    <h3>Static目录</h3>
    <pre>$(ls -la /app/backend/static 2>/dev/null || echo "目录不存在或为空")</pre>
  </div>
  
  <div class="debug-section">
    <h2>配置信息</h2>
    <pre>配置文件: /app/backend/config.json
内容:
$(cat /app/backend/config.json 2>/dev/null || echo "无法读取配置文件")

静态文件目录配置: ${STATIC_DIR:-"./static"}</pre>
  </div>
  
  <div class="debug-section">
    <h2>环境变量</h2>
    <pre>$(env | grep -v PASSWORD | grep -v TOKEN | sort)</pre>
  </div>
  
  <div class="debug-section">
    <h2>系统信息</h2>
    <pre>容器启动时间: $(date)
Alpine版本: $(cat /etc/alpine-release)
可用内存: $(free -m | grep Mem | awk '{print $2}') MB
可用磁盘空间: $(df -h / | tail -1 | awk '{print $4}')</pre>
  </div>
</body>
</html>
EOF
  log_info "已创建增强版调试页面"
else
  log_info "前端静态文件检查通过，找到了 $static_files_count 个文件"
  # 打印一些文件列表以便调试
  log_info "前端静态文件列表（限制10个）:"
  find /app/backend/static -type f | head -10
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

# 启动服务器前执行最后的文件检查
if [ ! -f "/app/backend/static/index.html" ]; then
  log_warn "在启动前检测到静态index.html仍然缺失，最后尝试创建..."
  mkdir -p /app/backend/static
  echo '<html><body><h1>GOSYNFLOOD管理平台</h1><p>紧急备用页面</p></body></html>' > /app/backend/static/index.html
fi

# 启动服务器
log_success "所有检查通过，正在启动服务器..."
cd /app/backend
exec /app/bin/attack-server -config /app/backend/config.json 