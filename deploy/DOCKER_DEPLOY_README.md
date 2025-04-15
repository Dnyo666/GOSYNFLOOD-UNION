# Docker部署指南

本文档详细说明了如何使用Docker部署gosynflood-union管理平台，以及如何解决可能遇到的常见问题。

## 主要修改内容

我们对Docker部署配置进行了以下优化，解决了"找不到attack-manager镜像"等问题：

1. **docker-compose.yml修改**:
   - 移除了旧版本的`version: '3.8'`字段，避免Docker Compose V2版本警告
   - 调整了构建配置，添加了`no_cache: true`选项确保始终重新构建镜像
   - 修改了镜像标签为`gosynflood-manager:local`，明确表示这是本地构建镜像

2. **Dockerfile优化**:
   - 调整了依赖安装顺序，先处理Go模块依赖再复制源代码
   - 添加了构建验证步骤，检查并显示Vue输出目录配置
   - 修复了前端构建产物路径问题，从`/app/dist/`修改为`/app/backend/static/`
   - 添加了错误处理和构建日志，便于排查问题
   - 显式处理Go依赖，特别是自动添加gorilla/mux依赖到go.mod文件

3. **部署脚本新增**:
   - 添加了Linux/Mac脚本(`deploy/docker-deploy.sh`)和Windows脚本(`deploy/docker-deploy.bat`)
   - 脚本提供了详细的部署过程反馈和错误处理
   - 自动处理依赖项检查、文件权限设置、构建缓存清理等常见问题
   - 添加了自动修复Go依赖问题的功能，包括检查并添加缺失的依赖

## 快速部署步骤

### Linux/Mac环境:

```bash
# 克隆项目
git clone https://github.com/Dnyo666/gosynflood-union.git
cd gosynflood-union

# 为脚本添加执行权限
chmod +x deploy/docker-deploy.sh

# 运行部署脚本
./deploy/docker-deploy.sh
```

### Windows环境:

```cmd
REM 克隆项目
git clone https://github.com/Dnyo666/gosynflood-union.git
cd gosynflood-union

REM 运行部署脚本
deploy\docker-deploy.bat
```

## 手动部署步骤

如果您不想使用部署脚本，可以手动执行以下命令：

```bash
# 预处理Go依赖
cd backend
# 检查并添加gorilla/mux依赖
grep -q "github.com/gorilla/mux" go.mod || echo "require github.com/gorilla/mux v1.8.0" >> go.mod
go mod tidy
go mod download
cd ..

# 确保目录存在
mkdir -p backend/static

# 先构建镜像
ADMIN_TOKEN=$(openssl rand -hex 16) docker-compose build --no-cache

# 再启动容器
ADMIN_TOKEN=$(openssl rand -hex 16) docker-compose up -d
```

**注意**: 构建和启动必须分为两个步骤，或使用`--build`参数，否则可能会尝试拉取不存在的远程镜像。

## 前端路由与登录说明

由于本项目使用Vue的history模式构建前端路由，部署时需要注意以下几点：

1. **登录流程**:
   - 当用户首次访问系统或未登录时，会被重定向到`/login-root.html`
   - `login-root.html`会自动重定向到`/static/login.html`，这是实际的登录页面
   - 用户输入管理员令牌后，会被重定向到主页

2. **路由处理**:
   - 静态资源位于`/app/backend/static`目录，通过`/static/`路径访问
   - 前端路由(如`/attack`, `/servers`等)在服务器端全部重定向到`index.html`，由Vue Router处理
   - 在部署脚本中已自动调整配置文件，确保静态文件路径正确

3. **静态文件检查**:
   - 部署脚本会检查登录页面和相关文件是否存在，缺失时会自动创建基本版本
   - 如果发现前端页面无法访问，可尝试重新构建Docker镜像，或手动复制静态文件

4. **认证令牌**:
   - 登录成功后，令牌保存在浏览器的localStorage中
   - API请求自动附加令牌在`X-Admin-Token`请求头中
   - 管理员令牌在Docker容器中通过环境变量`ADMIN_TOKEN`设置

5. **关于静态文件路径配置**:
   - 静态文件通过`/static/`URL前缀访问，但物理路径是`/app/backend/static`
   - 系统会自动处理路径映射，确保静态资源能够正确加载
   - 如果遇到登录页面404错误，可以访问测试页面 `/static/path-test.html` 验证配置

### 静态文件路径问题排查

如果遇到登录页面404错误，可能是由于以下原因：

1. **静态文件服务配置问题**:
   ```
   访问/static/login.html时出现404错误
   ```
   
   解决方案：
   - 确认`/app/backend/static`目录中存在`login.html`文件
   - 检查服务器日志，查看实际请求路径
   - 可以尝试手动将登录页面文件复制到正确位置：
   ```bash
   docker exec -it gosynflood-manager cp /app/backend/static/login.html /app/backend/static/login.html
   ```

2. **路径重定向问题**:
   如果login-root.html显示但无法重定向到登录页面，可以尝试：
   ```bash
   # 进入容器
   docker exec -it gosynflood-manager sh
   
   # 检查静态文件目录
   ls -la /app/backend/static
   
   # 确认配置文件中的静态目录设置
   cat /app/backend/config.json | grep staticDir
   ```

## 常见问题解决

1. **找不到attack-manager镜像错误**:
   ```
   Warning pull access denied for gosynflood-manager, repository does not exist or may require 'docker login'
   ```
   
   解决方案: 必须先构建镜像，再启动容器
   ```bash
   docker-compose build --no-cache
   docker-compose up -d
   ```

2. **Go依赖问题(missing go.sum entry或not a known dependency)**:
   ```
   go: github.com/gorilla/mux@v1.8.0: missing go.sum entry
   go: module github.com/gorilla/mux: not a known dependency
   ```
   
   解决方案: 
   ```bash
   # 添加缺失的gorilla/mux依赖
   echo "require github.com/gorilla/mux v1.8.0" >> backend/go.mod
   
   # 确保go.sum文件存在
   touch backend/go.sum
   touch go.sum
   
   # 下载依赖
   cd backend
   go mod tidy
   go mod download
   cd ..
   
   # 重新构建
   docker-compose build --no-cache
   ```

3. **静态文件路径404错误（/login-root.html或/static/login.html不可访问）**:
   ```
   404 page not found - 当尝试访问/login-root.html或/static/login.html时
   ```
   
   解决方案:
   ```bash
   # 进入容器
   docker exec -it gosynflood-manager sh
   
   # 检查静态文件目录结构
   ls -la /app/backend/static
   
   # 确保login.html存在
   if [ ! -f "/app/backend/static/login.html" ]; then
     echo "找不到login.html文件，从系统其他位置搜索..."
     find_login=$(find /app -name "login.html" -type f)
     if [ ! -z "$find_login" ]; then
       echo "找到login.html: $find_login"
       cp "$find_login" /app/backend/static/login.html
     else
       echo "无法找到login.html, 创建默认版本..."
       # 创建默认的login.html文件
       cat > /app/backend/static/login.html << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <title>登录</title>
</head>
<body>
  <h1>登录</h1>
  <form id="login-form">
    <input type="password" id="admin-token" placeholder="管理员令牌">
    <button type="submit">登录</button>
  </form>
  <script>
    document.getElementById('login-form').addEventListener('submit', function(e) {
      e.preventDefault();
      const token = document.getElementById('admin-token').value;
      fetch('/api/login', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({adminToken: token})
      })
      .then(r => r.json())
      .then(data => {
        if(data.success) {
          localStorage.setItem('adminToken', token);
          window.location.href = '/';
        } else {
          alert('登录失败');
        }
      });
    });
  </script>
</body>
</html>
EOF
     fi
   fi
   
   # 确保login-root.html正确重定向
   echo '<!DOCTYPE html><html><head><meta charset="UTF-8"><meta http-equiv="refresh" content="0; url=/static/login.html"><title>重定向到登录页</title></head><body><p>正在重定向到登录页...</p><script>window.location.href = "/static/login.html";</script></body></html>' > /app/backend/static/login-root.html
   
   # 退出容器
   exit
   
   # 重启容器
   docker restart gosynflood-manager
   ```
   
   **静态文件路径配置说明**:
   - 系统使用多级路由处理静态文件：
     - `/static/*` - 直接由静态文件服务器处理，无需认证
     - `/login-root.html` - 特殊处理，直接提供`/app/backend/static/login.html`文件
     - 其他路径 - 由FrontendAuthMiddleware处理，需要认证
     
   - 登录流程：
     1. 未认证用户访问任何受保护页面会被重定向到`/login-root.html`
     2. `/login-root.html`会再次重定向到`/static/login.html`
     3. 用户在登录页输入令牌验证通过后，会被重定向到原始请求页面
     
   - 如果遇到404错误，可通过访问`/static/path-test.html`测试页面来验证静态文件路径配置

4. **认证令牌无效问题(登录失败：令牌无效)**:
   ```
   {"error":"登录失败：令牌无效"}
   ```
   
   解决方案:
   ```bash
   # 检查容器中auth.go文件的令牌配置
   docker exec gosynflood-manager cat /app/backend/middleware/auth.go | head -20
   
   # 如果发现存在重复的package定义或者AdminToken定义，这表示文件内容出现了错误
   # 使用以下命令完全重写auth.go文件:
   
   docker exec gosynflood-manager sh -c "cat > /app/backend/middleware/auth.go << 'EOF'
package middleware

import (
	\"encoding/json\"
	\"io\"
	\"net/http\"
	\"strings\"
	\"time\"
	\"path/filepath\"
	\"os\"
)

// 配置保存在内存中的安全令牌
var (
	AdminToken = \"您的令牌值\" // 替换为您的实际令牌
)

// AdminAuthMiddleware 验证需要管理员权限的请求
func AdminAuthMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := \"\"
		authHeader := r.Header.Get(\"X-Admin-Token\")
		if authHeader != \"\" {
			token = authHeader
		}
		
		if token == \"\" && (r.Method == \"POST\" || r.Method == \"PUT\") {
			bodyBytes, err := io.ReadAll(r.Body)
			if err == nil {
				r.Body.Close()
				r.Body = io.NopCloser(strings.NewReader(string(bodyBytes)))
				var requestData map[string]interface{}
				if err := json.Unmarshal(bodyBytes, &requestData); err == nil {
					if adminToken, ok := requestData[\"adminToken\"].(string); ok && adminToken != \"\" {
						token = adminToken
					}
				}
			}
		}
		
		if token == \"\" {
			if paramToken := r.URL.Query().Get(\"adminToken\"); paramToken != \"\" {
				token = paramToken
			}
		}
		
		if token == \"\" {
			if cookie, err := r.Cookie(\"admin_token\"); err == nil && cookie.Value != \"\" {
				token = cookie.Value
			}
		}
		
		if token == \"\" || token != AdminToken {
			w.Header().Set(\"Content-Type\", \"application/json\")
			w.WriteHeader(http.StatusUnauthorized)
			json.NewEncoder(w).Encode(map[string]string{
				\"error\": \"需要有效的管理员令牌\",
			})
			return
		}
		
		next(w, r)
	}
}
EOF"
   
   # 这只是auth.go文件的开头部分，完整版本请参考源代码
   # 重启容器生效
   docker restart gosynflood-manager
   ```
   
   **错误原因说明**：
   此错误通常是由于容器中的auth.go文件内容被错误修改，特别是在以下情况发生：
   - 文件中包含重复的package声明
   - AdminToken变量定义部分出现格式错误或被重复定义
   - 文件中包含了原始Go代码的文本字符串表示，而不是有效的Go代码
   
   **预防措施**：
   - 使用最新版本的deploy/docker/start.sh，它包含了改进的令牌更新方法
   - 避免直接编辑容器内部的文件
   - 在修改令牌后，始终检查auth.go文件的内容验证是否正确

4. **前端构建产物路径错误**:
   ```