# SYN洪水攻击管理平台 (GOSYNFLOOD-UNION)

这是一个基于gosynflood工具的分布式SYN洪水攻击管理平台，允许从一个中央控制台管理多个攻击服务器，并协调它们进行分布式攻击。

> **更新说明**: 
> 1. 启动脚本现已移至`deploy`目录，可通过`deploy/server-launcher.sh`（Linux/macOS）或`deploy\\server-launcher.bat`（Windows）运行。bin目录在.gitignore中，因此启动脚本不会在该目录中被版本控制。
> 2. 增强了安装脚本，添加了Node.js自动检测和安装功能，并支持使用Docker构建前端。
> 3. 支持在无Node.js环境的情况下，自动切换到Docker构建前端，大大提高了部署灵活性。

## 自动依赖检测

安装脚本现在支持自动检测和安装以下依赖：

1. **Go**：安装脚本会检测并安装Go环境，确保版本兼容性
2. **Node.js**：对于管理模式安装，脚本会检测Node.js环境，必要时提供安装选项
   - 如检测不到Node.js，脚本会提示是否安装
   - 支持通过系统包管理器（apt、yum等）或NVM进行安装
   - 自动验证Node.js版本是否满足要求（建议v12+）
3. **Docker支持**：如果系统中没有Node.js但有Docker，脚本会自动使用Docker构建前端
   - 脚本会自动创建必要的Dockerfile
   - 使用Docker隔离构建环境，避免污染系统
   - 构建完成后自动将产物复制到正确位置

## 安装选项

安装时可以使用以下选项：

```bash
./deploy/setup.sh --help
```

特别说明：
- 使用 `--no-frontend` 可跳过前端构建
- 使用 `--non-interactive` 进行自动安装，此模式下：
  - 如果检测不到Node.js但有Docker，会自动使用Docker构建前端
  - 如果检测不到Node.js也没有Docker，会自动跳过前端构建
- 如果在交互模式下检测不到Node.js，会询问是否安装Node.js或跳过前端构建

## 警告

**本工具仅供授权的网络安全测试、教育和研究目的使用。**

未经授权对计算机系统和网络发起攻击是违法的，可能导致严重的法律后果。使用者需承担所有使用本工具的责任和后果。

## 系统架构详解

该平台采用分布式架构，由三个主要组件组成：

### 1. 前端 Web 界面
- 基于Vue.js构建的响应式用户界面
- 提供直观的仪表盘，展示攻击数据和服务器状态
- 实时更新攻击统计信息和服务器状态
- 支持多用户同时访问和操作

### 2. 后端 API 服务
- 使用Go语言开发的高性能服务器应用
- RESTful API接口，便于集成和扩展
- WebSocket实时数据推送
- 集中管理所有攻击服务器和任务

### 3. 客户端代理
- 在每台攻击服务器上运行的轻量级Go程序
- 与中央管理服务器保持心跳连接
- 接收并执行攻击指令
- 收集并上报攻击数据

### 通信流程

1. **前端与后端通信**：通过HTTP API和WebSocket连接
2. **后端与代理通信**：使用HTTP轮询或WebSocket（当前实现使用HTTP轮询）
3. **安全认证**：使用API密钥确保通信安全

## 功能特性

- 集中管理多台攻击服务器
- 实时监控攻击状态和效果
- 配置和调度攻击任务
- 自动同步和状态报告
- 可扩展架构，支持添加更多攻击服务器
- 支持自定义攻击参数（目标、端口、持续时间等）
- 支持多服务器协同攻击同一目标
- 攻击任务历史记录与回放分析

## 环境要求

### 管理服务器要求
- 操作系统：Linux、macOS或Windows
- Go 1.15+
- Node.js 14+
- 开放的网络端口（默认31457）
- 至少2GB RAM和500MB可用存储空间

### 攻击服务器要求
- 操作系统：Linux（推荐Ubuntu 18.04+）
- Go 1.15+
- 已安装gosynflood工具
- Root权限（原始套接字需要）
- 稳定的网络连接

## 安装和配置

### 1. 获取源代码

```bash
git clone https://github.com/Dnyo666/gosynflood-union.git
cd gosynflood-union
```

### 2. 安装方式

#### 2.1 快速安装（自动）

使用提供的安装脚本可以自动完成所有构建步骤。安装脚本支持两种安装模式：管理主机（manager）和攻击主机（agent）。

##### 2.1.1 管理主机安装

在中央管理服务器上运行：

```bash
# 赋予脚本执行权限
chmod +x deploy/setup.sh

# 运行安装脚本（管理主机模式）
./deploy/setup.sh --mode=manager --admin-token="your-secure-admin-token"
```

如果不提供管理员令牌，脚本会自动生成一个随机令牌。请务必记录此令牌，它将用于管理操作和配置攻击代理。

##### 2.1.2 攻击主机安装

在每台攻击服务器上运行：

```bash
# 赋予脚本执行权限
chmod +x deploy/setup.sh

# 运行安装脚本（攻击主机模式）
./deploy/setup.sh --mode=agent --manager-url="http://管理服务器IP:31457" --agent-id=1 --agent-key="从管理界面获取的API密钥"
```

脚本会自动创建一个启动脚本，简化后续的攻击代理启动过程。

##### 2.1.3 完整的脚本选项

安装脚本支持以下选项：
- `--mode=(manager|agent)`: 安装模式，管理服务器或攻击代理
- `--admin-token=<令牌>`: 设置管理员令牌（仅管理服务器模式）
- `--manager-url=<URL>`: 管理服务器URL（仅攻击代理模式）
- `--agent-key=<密钥>`: 攻击代理的API密钥（仅攻击代理模式）
- `--agent-id=<ID>`: 攻击代理的ID（仅攻击代理模式）
- `--no-frontend`: 不构建前端（仅管理服务器模式）
- `--no-backend`: 不构建后端（仅管理服务器模式）
- `--no-client`: 不构建客户端代理
- `--help`: 显示帮助信息

#### 2.2 手动安装

如果需要更多控制或自动安装脚本无法在您的环境中正常工作，可以按照以下步骤手动安装：

##### 2.2.1 构建后端

```bash
cd backend
go mod tidy
go build -o ../bin/attack-server main.go
```

##### 2.2.2 构建前端

```bash
cd frontend
npm install
npm run build
# 复制前端文件到后端的静态文件目录
cp -r dist/* ../backend/static/
```

##### 2.2.3 构建客户端代理

```bash
cd client
go mod tidy
go build -o ../bin/attack-agent agent.go
```

### 3. 配置系统

#### 3.1 后端配置

创建或修改 `backend/config.json` 文件：

```json
{
  "host": "0.0.0.0",
  "port": 31457,
  "staticDir": "./static",
  "logLevel": "info",
  "allowedOrigins": "*",
  "dataDir": "../data"
}
```

配置字段说明：
- `host`: 监听的网络接口，设置为"0.0.0.0"允许从任何IP地址访问服务器
- `port`: 服务器监听端口
- `staticDir`: 静态文件目录
- `allowedOrigins`: 允许的CORS跨域来源
- `dataDir`: 数据存储目录

#### 3.2 安全配置

为提高安全性，请修改 `backend/middleware/auth.go` 中的默认令牌：

```go
var (
    AdminToken = "your-secure-token-here" 
)
```

## 启动服务

### 1. 管理服务器启动

安装脚本提供了启动脚本，可以方便地在后台运行服务器。**注意：启动脚本位于deploy目录而不是bin目录中**。

#### Linux/macOS环境：

```bash
# 赋予启动脚本执行权限
chmod +x deploy/server-launcher.sh

# 在后台运行服务器
deploy/server-launcher.sh

# 查看所有可用选项
deploy/server-launcher.sh --help

# 检查服务器状态
deploy/server-launcher.sh --status

# 停止服务器
deploy/server-launcher.sh --kill
```

#### Windows环境：

```powershell
# 使用批处理文件启动
deploy\server-launcher.bat

# 查看所有可用选项
deploy\server-launcher.bat --help

# 检查服务器状态
deploy\server-launcher.bat --status

# 停止服务器
deploy\server-launcher.bat --kill
```

启动脚本会显示可用的访问URL，包括：
- 本地访问：http://localhost:31457
- 远程访问：http://[服务器IP]:31457

#### 设置系统服务（可选）

##### Linux（systemd）:

创建systemd服务文件：

```bash
sudo cat > /etc/systemd/system/gosynflood-manager.service << EOF
[Unit]
Description=GOSYNFLOOD-UNION Attack Manager Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/gosynflood-union
ExecStart=/root/gosynflood-union/bin/attack-server -config /root/gosynflood-union/backend/config.json
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 重新加载systemd配置
sudo systemctl daemon-reload

# 启动服务
sudo systemctl start gosynflood-manager

# 设置开机自启动
sudo systemctl enable gosynflood-manager

# 查看服务状态
sudo systemctl status gosynflood-manager
```

##### Windows服务（使用NSSM）:

1. 下载NSSM（Non-Sucking Service Manager）: https://nssm.cc/download
2. 解压后，使用管理员权限运行cmd:

```cmd
C:\path\to\nssm.exe install GOSYNFLOOD-MANAGER "E:\path\to\gosynflood-union\bin\attack-server.exe" "-config E:\path\to\gosynflood-union\backend\config.json"
C:\path\to\nssm.exe set GOSYNFLOOD-MANAGER AppDirectory "E:\path\to\gosynflood-union"
C:\path\to\nssm.exe start GOSYNFLOOD-MANAGER
```

### 2. 部署前端（生产环境）

将`frontend/dist`目录中的文件复制到Web服务器（如Nginx）的静态文件目录中，或使用后端的静态文件服务功能。
自动安装脚本已自动完成此操作，无需单独执行。

### 3. 攻击代理启动

在每台攻击服务器上：

#### 3.1 自动安装方式

如果使用自动安装脚本（agent模式），可以直接运行：

```bash
cd bin
./start-agent.sh
```

#### 3.2 手动配置方式

手动配置时，需要提供相关参数：

```bash
cd bin
./attack-agent -id <服务器ID> -key "<API密钥>" -master "<管理服务器URL>" -tools "<gosynflood工具路径>"
```

参数说明：
- `-id`: 服务器唯一标识符（整数）
- `-key`: 与管理平台通信的API密钥（在管理平台添加服务器时生成）
- `-master`: 管理服务器URL，如"http://192.168.1.100:31457"
- `-tools`: gosynflood工具的路径，默认为"/usr/local/bin"

## 使用指南

### 1. 访问管理平台

在浏览器中访问：

```
http://[管理服务器IP]:31457
```

首次使用时，系统会显示空白的仪表盘。

### 2. 添加攻击服务器

1. 在仪表盘界面点击"添加服务器"按钮
2. 填写服务器信息：
   - 服务器名称：用于识别服务器的友好名称
   - IP地址：服务器的IP地址
   - API端口：服务器上代理监听的端口（通常为默认值）
   - API密钥：用于身份验证的密钥（请使用强密码）
3. 点击"添加"保存服务器信息
4. 在攻击服务器上启动代理，使用相同的ID和API密钥
5. 服务器状态应该在几秒钟内变为"在线"

### 3. 配置攻击任务

1. 点击任何在线服务器的"发起攻击"按钮，或通过导航菜单创建新任务
2. 填写攻击配置：
   - 攻击名称：为任务提供描述性名称
   - 目标IP地址：攻击目标的IP地址
   - 目标端口：目标服务的端口（如80用于HTTP）
   - 选择参与攻击的服务器（可多选）
   - 高级选项：
     - 攻击持续时间：设置攻击自动停止的时间（秒），0表示不限时间
     - 每秒数据包限制：限制发送速率，0表示不限速
3. 点击"开始攻击"按钮
4. 在确认对话框中再次确认攻击信息
5. 点击"确认发起攻击"开始执行

### 4. 监控攻击

1. 攻击开始后，可以在仪表盘的"当前攻击"部分查看实时状态
2. 每个攻击任务显示以下信息：
   - 目标IP和端口
   - 使用的服务器数量
   - 运行时间
   - 已发送的数据包数量
   - 当前发包速率
3. 实时统计信息会自动更新，无需刷新页面

### 5. 停止攻击

1. 在"当前攻击"列表中找到要停止的攻击
2. 点击"停止攻击"按钮
3. 攻击将在所有参与的服务器上停止
4. 攻击记录将保存到历史记录中

### 6. 管理服务器

1. 查看服务器详情：点击服务器列表中的"详情"按钮
2. 服务器详情页面显示：
   - 服务器状态和资源使用情况
   - 历史攻击记录
   - 网络接口信息
3. 删除服务器：在服务器详情页面使用"删除服务器"功能

## 故障排除

### 常见问题及解决方案

#### 服务器无法连接到管理平台

1. 检查网络连接和防火墙设置
2. 确认管理服务器URL配置正确
3. 验证API密钥与管理平台中的设置匹配
4. 检查管理服务器日志中的错误信息
5. 如果使用0.0.0.0地址绑定，确保服务器防火墙允许31457端口的访问

#### 无法从远程访问管理界面

1. 确认配置文件中的`host`设置为"0.0.0.0"
2. 检查服务器防火墙是否允许31457端口的入站连接
3. 尝试使用服务器的实际IP地址而不是localhost
4. 运行`deploy/server-launcher.sh --status`检查服务器是否正在运行
5. 查看日志文件（默认为`logs/server.log`）获取详细错误信息

#### 攻击任务创建后无法启动

1. 确认所选服务器状态为"在线"
2. 检查目标IP和端口格式是否正确
3. 验证服务器上的gosynflood工具是否可用
4. 查看服务器代理日志以获取详细错误信息

#### 统计数据不更新

1. 检查WebSocket连接是否正常
2. 确认浏览器控制台中没有JavaScript错误
3. 尝试刷新页面重新建立连接

#### 服务器代理频繁崩溃

1. 检查系统资源使用情况（CPU、内存、网络）
2. 确认gosynflood工具正确安装
3. 验证运行代理的用户有足够权限
4. 检查系统日志中的相关错误

## 更新系统

更新系统到最新版本：

```bash
git pull
./deploy/setup.sh
```

## 安全建议

### 保护管理平台

1. **使用HTTPS**：在生产环境中配置SSL证书保护通信
2. **设置防火墙**：限制管理平台只能从特定IP地址访问
3. **使用强密码**：为API密钥使用复杂、长度充分的随机字符串
4. **定期更新**：及时应用安全更新和补丁

### 合法使用注意事项

1. **获取授权**：仅在获得明确书面授权的系统上进行测试
2. **限制范围**：明确测试范围和目标，避免意外影响其他系统
3. **保持记录**：记录所有测试活动，包括时间、目标和参数
4. **报告发现**：向系统所有者报告发现的任何安全问题

## 项目贡献

欢迎通过以下方式参与项目：

1. 报告Bug和提出功能建议
2. 提交代码改进和新功能
3. 改进文档和使用指南
4. 分享使用经验和最佳实践

请确保所有贡献符合项目编码规范和设计理念。

## 文件结构

```
.
├── frontend/           # Vue.js前端应用
│   ├── src/            # 前端源代码
│   │   ├── views/      # 页面组件
│   │   ├── components/ # 通用组件
│   │   ├── api/        # API调用
│   │   ├── store/      # Vuex状态管理
│   │   └── router/     # 前端路由
├── backend/            # Go后端API服务
│   ├── main.go         # 主程序入口
│   └── static/         # 静态文件服务目录
├── client/             # 客户端代理
│   ├── agent.go        # 代理入口
│   └── ...
├── bin/                # 编译后的二进制文件
├── docs/               # 文档
└── deploy/             # 部署脚本
```

## 开发与扩展

- 前端使用Vue.js和Element UI
- 后端使用Go标准库和Gorilla Mux
- 新功能开发请遵循现有代码风格
- 添加新的攻击类型需要修改客户端代理和服务器端处理逻辑

### 开发指南

1. **添加新的攻击类型**：
   - 在客户端代理中添加新攻击命令支持
   - 在后端API中添加相应的命令处理逻辑
   - 更新前端界面以支持新攻击类型的配置

2. **扩展服务器监控功能**：
   - 在客户端代理中添加额外的系统监控指标
   - 修改心跳协议以包含新的监控数据
   - 在前端仪表盘中添加新的监控图表

3. **改进安全性**：
   - 实现更强的身份验证机制
   - 添加用户角色和权限控制
   - 实现API请求速率限制和监控

## 许可

本项目采用MIT许可证。请参阅LICENSE文件获取详情。

## Docker部署管理平台

除了使用安装脚本，您还可以使用Docker一键部署完整的管理平台。**这是一个完全独立的部署方案**，与常规的脚本安装互不影响。此方法**仅适用于管理服务器**，节点机仍需使用常规安装方式。

### 前提条件

- 已安装Docker (17.09.0+)
- 已安装Docker Compose (1.17.0+)

### 快速开始

#### 方法一：使用部署脚本（推荐）

我们提供了一个简便的部署脚本，可以自动处理常见的Docker部署问题：

**Linux/Mac环境**:
```bash
# 为脚本添加执行权限
chmod +x deploy/docker-deploy.sh

# 使用随机生成的管理员令牌运行
./deploy/docker-deploy.sh

# 或使用自定义管理员令牌
./deploy/docker-deploy.sh --token your-secure-token
```

**Windows环境**:
```cmd
# 使用随机生成的管理员令牌运行
deploy\docker-deploy.bat

# 或使用自定义管理员令牌
deploy\docker-deploy.bat --token your-secure-token
```

部署脚本会自动：
- 检查必要的Docker环境
- 清理旧的Docker构建缓存
- 确保项目目录权限正确
- 构建并启动容器
- 提供详细的状态反馈和错误处理

#### 方法二：手动部署

如果您不想使用部署脚本，也可以手动执行以下步骤：

1. 创建`docker-compose.yml`文件：

```yaml
services:
  attack-manager:
    container_name: gosynflood-manager
    build:
      context: .
      dockerfile: Dockerfile
      no_cache: true
    image: gosynflood-manager:local
    ports:
      - "31457:31457"
    volumes:
      - attack_data:/app/data
    environment:
      - ADMIN_TOKEN=${ADMIN_TOKEN:-change-me-to-secure-token}
    restart: unless-stopped

volumes:
  attack_data:
    name: gosynflood_attack_data
```

2. 创建`Dockerfile`：

```dockerfile
FROM golang:1.18-alpine AS backend-builder

WORKDIR /app

# 安装必要的构建工具
RUN apk add --no-cache git

# 复制Go模块文件
COPY go.mod ./
COPY backend/go.mod ./backend/

# 先处理后端依赖
RUN cd backend && go mod tidy && go mod download

# 复制后端源代码
COPY backend/ ./backend/
COPY *.go ./

# 构建后端
RUN cd backend && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /app/bin/attack-server main.go

# 前端构建阶段
FROM node:16-alpine AS frontend-builder

WORKDIR /app

# 复制前端依赖文件
COPY frontend/package*.json ./

# 安装依赖
RUN npm install --no-fund --no-audit --production=false

# 复制前端源代码
COPY frontend/ ./

# 构建前端
RUN npm run build

# 最终阶段
FROM alpine:3.16

WORKDIR /app

# 安装运行时依赖
RUN apk add --no-cache ca-certificates tzdata

# 创建必要的目录
RUN mkdir -p /app/bin /app/data /app/backend/static

# 从构建阶段复制构建产物
COPY --from=backend-builder /app/bin/attack-server /app/bin/
COPY --from=frontend-builder /app/backend/static/ /app/backend/static/
COPY backend/config.json /app/backend/

# 设置默认的管理员令牌（在启动时可以通过环境变量覆盖）
ENV ADMIN_TOKEN="change-me-to-secure-token"

# 创建并配置auth.go文件
RUN mkdir -p /app/backend/middleware
RUN echo 'package middleware\n\nimport (\n\t"net/http"\n)\n\nvar (\n    AdminToken = "'$ADMIN_TOKEN'" \n)\n\n// AdminAuthMiddleware 验证管理员令牌\nfunc AdminAuthMiddleware(next http.HandlerFunc) http.HandlerFunc {\n\treturn func(w http.ResponseWriter, r *http.Request) {\n\t\ttoken := r.Header.Get("X-Admin-Token")\n\t\tif token != AdminToken {\n\t\t\thttp.Error(w, "未授权访问", http.StatusUnauthorized)\n\t\t\treturn\n\t\t}\n\t\tnext(w, r)\n\t}\n}' > /app/backend/middleware/auth.go

# 暴露服务端口
EXPOSE 31457

# 创建启动脚本
RUN echo '#!/bin/sh\n\n# 更新管理员令牌\nif [ ! -z "$ADMIN_TOKEN" ]; then\n  sed -i "s/AdminToken = \".*\"/AdminToken = \"$ADMIN_TOKEN\"/g" /app/backend/middleware/auth.go\n  echo "管理员令牌已更新"\nfi\n\n# 启动服务器\ncd /app\nexec /app/bin/attack-server -config /app/backend/config.json\n' > /app/start.sh && chmod +x /app/start.sh

# 设置启动命令
CMD ["/app/start.sh"]
```

3. 执行构建和部署命令：

```bash
# 清理旧的构建缓存（可选但推荐）
docker builder prune -f

# 先构建镜像（指定--no-cache避免使用缓存）
ADMIN_TOKEN=$(openssl rand -hex 16) docker-compose build --no-cache

# 然后启动容器
ADMIN_TOKEN=$(openssl rand -hex 16) docker-compose up -d
```

> **重要提示**：一定要先使用`docker-compose build`命令构建镜像，避免Docker尝试从远程仓库拉取不存在的镜像。

4. 查看生成的管理员令牌：

```bash
docker logs gosynflood-manager | grep "管理员令牌已更新"
```

5. 访问管理界面：
   - 本地访问：http://localhost:31457
   - 远程访问：http://<服务器IP>:31457

### Docker管理命令

```bash
# 查看容器状态
docker ps -a --filter "name=gosynflood-manager"

# 查看容器日志
docker logs gosynflood-manager

# 停止服务
docker-compose down

# 重启服务
docker-compose restart

# 重建镜像并重启（完整重建）
docker-compose build --no-cache && docker-compose up -d
```

### 与攻击节点集成

Docker部署的管理服务器可以与通过脚本安装的攻击节点协同工作。在攻击节点上使用以下命令安装客户端代理：

```bash
./deploy/setup.sh --mode=agent --manager-url="http://管理服务器IP:31457" --agent-id=1 --agent-key="从管理界面获取的API密钥"
```

> **注意**：Docker部署方案完整包含了管理平台的前端、后端、API和管理功能，只是将它们运行在Docker容器中而非直接运行在主机系统上。数据持久化存储在Docker卷`gosynflood_attack_data`中，确保定期备份重要数据。

### Docker部署故障排除

如果您在Docker部署过程中遇到问题，以下是一些常见问题和解决方案：

1. **找不到docker镜像错误**：如出现类似"requested access to the resource is denied"或"repository does not exist"错误：
   ```bash
   # 不要使用一步到位的命令：
   # ADMIN_TOKEN=xxx docker-compose up -d
   
   # 请改用分步命令确保先构建再启动：
   ADMIN_TOKEN=xxx docker-compose build --no-cache
   ADMIN_TOKEN=xxx docker-compose up -d
   
   # 或使用我们提供的部署脚本
   ./deploy/docker-deploy.sh
   ```

2. **Go依赖问题**：如果出现依赖错误，请按以下步骤操作：
   ```bash
   # 进入后端目录处理依赖
   cd backend 
   go mod tidy
   go mod download
   
   # 回到根目录，重新构建
   cd .. 
   docker-compose build --no-cache
   ```

3. **前端构建失败**：如果前端构建阶段失败，可以尝试：
   ```bash
   # 清除Node.js缓存
   docker builder prune -f
   
   # 确保frontend目录权限正确
   chmod -R 755 frontend/
   
   # 重新构建
   docker-compose build --no-cache
   ```

4. **前端构建产物路径错误**：如果遇到找不到`/app/dist/`的错误，这是因为Vue.js配置中的输出目录被设置为`/app/backend/static/`：
   ```bash
   # 查看Vue输出目录配置
   cat frontend/vue.config.js | grep outputDir
   
   # 确保Dockerfile中的路径与Vue配置一致
   # COPY --from=frontend-builder /app/backend/static/ /app/backend/static/
   ```

5. **容器启动失败**：如果容器无法启动，可以检查日志：
   ```bash
   docker logs gosynflood-manager
   ```
   
   常见原因包括：
   - 端口31457已被占用：修改docker-compose.yml中的端口映射
   - 权限问题：确保数据卷挂载点有正确权限

6. **管理员令牌问题**：如果管理员令牌不起作用：
   ```bash
   # 停止并删除容器
   docker-compose down
   
   # 使用明确的令牌重新启动
   ADMIN_TOKEN="your-new-secure-token" docker-compose up -d
   
   # 确认令牌已更新
   docker logs gosynflood-manager | grep "管理员令牌已更新"
   ```

7. **Docker Compose版本警告**：如果您看到关于`version`属性过时的警告，可以从docker-compose.yml中移除version行，或升级到Docker Compose V2。