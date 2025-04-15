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
  
  # 确保静态文件目录存在，无论是相对路径还是绝对路径
  mkdir -p "/app/backend/static"
  
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
    
    # 修改config.json以使用绝对路径
    log_info "正在更新配置文件，将相对静态文件路径改为绝对路径..."
    sed -i "s|\"staticDir\": \"${STATIC_DIR}\"|\"staticDir\": \"/app/backend/static\"|g" /app/backend/config.json
    log_info "配置文件已更新，静态目录现在使用绝对路径: /app/backend/static"
  fi
else
  log_warn "无法解析配置文件中的staticDir，使用默认值"
  mkdir -p "/app/backend/static"
fi

# 检查认证中间件
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

# 确保登录页面存在
if [ ! -f "/app/backend/static/login.html" ]; then
  log_warn "警告: 找不到登录页面文件: /app/backend/static/login.html"
  log_info "创建基本登录页面..."
  
  mkdir -p /app/backend/static
  cat > /app/backend/static/login.html << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>GOSYNFLOOD管理平台 - 登录</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      margin: 0;
      padding: 0;
      background-color: #f4f7f9;
      color: #333;
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
    }
    .login-container {
      background-color: #fff;
      border-radius: 8px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.1);
      padding: 40px;
      width: 360px;
    }
    .header {
      text-align: center;
      margin-bottom: 30px;
    }
    .header h1 {
      color: #2c3e50;
      margin: 0;
      font-size: 28px;
      font-weight: 500;
    }
    .header p {
      color: #7f8c8d;
      margin-top: 10px;
      font-size: 16px;
    }
    .form-group {
      margin-bottom: 20px;
    }
    label {
      display: block;
      margin-bottom: 8px;
      font-weight: 500;
      color: #34495e;
    }
    input[type="password"] {
      width: 100%;
      padding: 12px;
      border: 1px solid #ddd;
      border-radius: 4px;
      box-sizing: border-box;
      font-size: 16px;
    }
    button {
      width: 100%;
      padding: 12px;
      background-color: #3498db;
      color: white;
      border: none;
      border-radius: 4px;
      cursor: pointer;
      font-size: 16px;
      transition: background-color 0.3s;
    }
    button:hover {
      background-color: #2980b9;
    }
    .alert {
      padding: 12px;
      border-radius: 4px;
      margin-bottom: 20px;
      display: none;
    }
    .alert-danger {
      background-color: #fee;
      color: #e74c3c;
      border: 1px solid #f5c6cb;
    }
    .alert-success {
      background-color: #d4edda;
      color: #155724;
      border: 1px solid #c3e6cb;
    }
  </style>
</head>
<body>
  <div class="login-container">
    <div class="header">
      <h1>GOSYNFLOOD管理平台</h1>
      <p>请输入管理员令牌进行登录</p>
    </div>
    
    <div id="alert-error" class="alert alert-danger"></div>
    <div id="alert-success" class="alert alert-success"></div>
    
    <form id="login-form">
      <div class="form-group">
        <label for="admin-token">管理员令牌</label>
        <input type="password" id="admin-token" name="adminToken" placeholder="请输入管理员令牌" required>
      </div>
      <button type="submit">登录</button>
    </form>
  </div>

  <script>
    document.addEventListener('DOMContentLoaded', function() {
      const loginForm = document.getElementById('login-form');
      const errorAlert = document.getElementById('alert-error');
      const successAlert = document.getElementById('alert-success');
      
      // 检查是否已有保存的令牌
      const savedToken = localStorage.getItem('adminToken');
      if (savedToken) {
        // 尝试自动验证
        verifyToken(savedToken);
      }
      
      loginForm.addEventListener('submit', function(e) {
        e.preventDefault();
        
        const adminToken = document.getElementById('admin-token').value.trim();
        if (!adminToken) {
          showError('请输入管理员令牌');
          return;
        }
        
        // 发送登录请求
        login(adminToken);
      });
      
      // 登录函数
      function login(token) {
        fetch('/api/login', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ adminToken: token }),
          credentials: 'same-origin'
        })
        .then(response => {
          if (!response.ok) {
            return response.json().then(data => {
              throw new Error(data.error || '登录失败');
            });
          }
          return response.json();
        })
        .then(data => {
          // 登录成功
          localStorage.setItem('adminToken', token);
          showSuccess('登录成功，正在跳转...');
          
          // 跳转到首页
          setTimeout(() => {
            window.location.href = '/';
          }, 1000);
        })
        .catch(error => {
          showError(error.message);
        });
      }
      
      // 验证已保存的令牌
      function verifyToken(token) {
        fetch('/api/servers', {
          headers: {
            'X-Admin-Token': token
          },
          credentials: 'same-origin'
        })
        .then(response => {
          if (response.ok) {
            // 令牌有效，跳转到首页
            window.location.href = '/';
          } else {
            // 令牌无效，清除
            localStorage.removeItem('adminToken');
          }
        })
        .catch(() => {
          // 发生错误，清除令牌
          localStorage.removeItem('adminToken');
        });
      }
      
      // 显示错误信息
      function showError(message) {
        errorAlert.textContent = message;
        errorAlert.style.display = 'block';
        successAlert.style.display = 'none';
      }
      
      // 显示成功信息
      function showSuccess(message) {
        successAlert.textContent = message;
        successAlert.style.display = 'block';
        errorAlert.style.display = 'none';
      }
    });
  </script>
</body>
</html>
EOF
  log_info "登录页面已创建"
fi

# 确保登录根页面存在
if [ ! -f "/app/backend/static/login-root.html" ]; then
  log_warn "警告: 找不到登录根页面文件: /app/backend/static/login-root.html"
  log_info "创建登录根页面..."
  
  mkdir -p /app/backend/static
  cat > /app/backend/static/login-root.html << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="refresh" content="0; url=/static/login.html">
  <title>重定向到登录页</title>
</head>
<body>
  <p>正在重定向到登录页...</p>
  <script>
    window.location.href = "/static/login.html";
  </script>
</body>
</html>
EOF
  log_info "登录根页面已创建"
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

# 在文件系统上查找并检测login.html文件的实际位置
find_login_html=$(find /app -name "login.html" -type f 2>/dev/null)
if [ ! -z "$find_login_html" ]; then
  log_info "在系统中找到login.html文件: $find_login_html"
  
  # 如果找到的文件不在/app/backend/static目录下，复制过去
  if [[ "$find_login_html" != "/app/backend/static/login.html" ]]; then
    log_info "复制login.html到正确位置: /app/backend/static/login.html"
    cp "$find_login_html" "/app/backend/static/login.html"
  fi
fi

# 创建测试页面验证静态文件路径
log_info "创建静态文件路径测试页面..."
mkdir -p /app/backend/static
cat > /app/backend/static/path-test.html << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <title>静态文件路径测试</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    .test-box { 
      border: 1px solid #ddd; 
      padding: 15px; 
      margin-bottom: 20px; 
      border-radius: 4px;
      background-color: #f9f9f9;
    }
    h1 { color: #333; }
    .success { color: green; }
    .error { color: red; }
    pre { background: #f5f5f5; padding: 10px; overflow-x: auto; }
  </style>
</head>
<body>
  <h1>静态文件路径测试页面</h1>
  
  <div class="test-box">
    <h2>当前页面信息</h2>
    <p>当前文件: <code>/app/backend/static/path-test.html</code></p>
    <p>访问URL: <code>/static/path-test.html</code></p>
    <p><span class="success">✓ 如果您能看到此页面，说明静态文件路由已正确配置</span></p>
  </div>
  
  <div class="test-box">
    <h2>静态资源链接测试</h2>
    <p>尝试访问以下链接：</p>
    <ul>
      <li><a href="/static/login.html">/static/login.html</a> - 登录页面</li>
      <li><a href="/login-root.html">/login-root.html</a> - 登录根页面</li>
      <li><a href="/">/</a> - 根路径 (前端首页)</li>
    </ul>
  </div>
  
  <div class="test-box">
    <h2>服务器配置信息</h2>
    <pre>
静态文件目录配置: ${STATIC_DIR:-"./static"}
静态文件实际路径: /app/backend/static
容器内实际文件列表: 
$(find /app/backend/static -type f | sort)
    </pre>
  </div>
</body>
</html>
EOF
log_info "静态文件路径测试页面已创建: /app/backend/static/path-test.html"
log_info "您可以通过访问 http://localhost:${PORT:-31457}/static/path-test.html 来测试静态文件路径"

# 启动服务器
log_success "所有检查通过，正在启动服务器..."
cd /app
exec /app/bin/attack-server -config /app/backend/config.json 