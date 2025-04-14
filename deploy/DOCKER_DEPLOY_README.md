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

3. **前端构建产物路径错误**:
   ```
   COPY --from=frontend-builder /app/dist/ /app/backend/static/: not found
   ```
   
   解决方案: 
   ```bash
   # 确保目标目录存在
   mkdir -p backend/static
   
   # 查看Vue配置中的输出目录
   cat frontend/vue.config.js | grep outputDir
   
   # 编辑Dockerfile，确保路径与Vue配置一致:
   # COPY --from=frontend-builder /app/backend/static/ /app/backend/static/
   ```

4. **构建超时或依赖下载慢**:
   ```
   ERROR: failed to solve: process "/bin/sh -c npm install --no-fund --no-audit --production=false" did not complete successfully
   ```
   
   解决方案:
   ```bash
   # 清理Docker构建缓存
   docker builder prune -f
   
   # 使用--no-cache选项强制重新构建
   docker-compose build --no-cache
   
   # 如果仍然失败，考虑设置npm镜像源
   npm config set registry https://registry.npmmirror.com/
   
   # 或者在Dockerfile中添加:
   # RUN npm config set registry https://registry.npmmirror.com/
   ```

## 其他Docker管理命令

```bash
# 查看容器日志
docker logs gosynflood-manager

# 停止容器
docker-compose down

# 重启容器
docker-compose restart

# 更新管理员令牌
ADMIN_TOKEN="new-token" docker-compose up -d
```

## 安全提示

- 请务必修改默认的管理员令牌
- 考虑设置防火墙限制对管理平台的访问
- 定期备份`gosynflood_attack_data`数据卷中的数据 