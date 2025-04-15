@echo off
REM Docker部署脚本 - Windows版本
REM 用于构建和部署gosynflood-union管理平台
REM 使用方法: deploy\docker-deploy.bat [--token YOUR_TOKEN]

setlocal enabledelayedexpansion

REM 颜色代码
set "GREEN=[92m"
set "YELLOW=[93m"
set "RED=[91m"
set "NC=[0m"

REM 输出函数
:info
echo %GREEN%[INFO]%NC% %~1
exit /b 0

:warn 
echo %YELLOW%[WARNING]%NC% %~1
exit /b 0

:error
echo %RED%[ERROR]%NC% %~1
exit /b 0

:success
echo %GREEN%[SUCCESS]%NC% %~1
exit /b 0

REM 检查Docker是否安装
where docker >nul 2>nul
if %ERRORLEVEL% neq 0 (
    call :error "Docker未安装，请先安装Docker"
    exit /b 1
)

REM 检查Docker Compose是否安装
where docker-compose >nul 2>nul
if %ERRORLEVEL% neq 0 (
    call :error "Docker Compose未安装，请先安装Docker Compose"
    exit /b 1
)

REM 生成随机管理员令牌（Windows下不能使用openssl，使用随机数替代）
set "ADMIN_TOKEN="
for /L %%i in (1, 1, 16) do (
    set /a "rand=!random! %% 16"
    if !rand! LSS 10 (
        set "ADMIN_TOKEN=!ADMIN_TOKEN!!rand!"
    ) else (
        if !rand!==10 set "ADMIN_TOKEN=!ADMIN_TOKEN!a"
        if !rand!==11 set "ADMIN_TOKEN=!ADMIN_TOKEN!b"
        if !rand!==12 set "ADMIN_TOKEN=!ADMIN_TOKEN!c"
        if !rand!==13 set "ADMIN_TOKEN=!ADMIN_TOKEN!d"
        if !rand!==14 set "ADMIN_TOKEN=!ADMIN_TOKEN!e"
        if !rand!==15 set "ADMIN_TOKEN=!ADMIN_TOKEN!f"
    )
)

REM 处理命令行参数
if "%~1"=="--token" (
    set "ADMIN_TOKEN=%~2"
)

REM 显示基本信息
call :info "开始部署gosynflood-union管理平台..."
call :info "管理员令牌: %ADMIN_TOKEN%"

REM 清理旧的构建缓存
call :info "清理Docker构建缓存..."
docker builder prune -f >nul 2>nul

REM 尝试停止并移除旧容器（如果存在）
call :info "移除旧容器（如果存在）..."
docker-compose down >nul 2>nul

REM 检查项目文件
if not exist "docker-compose.yml" (
    call :error "缺少必要的配置文件。请确保当前目录包含docker-compose.yml和Dockerfile文件"
    exit /b 1
)

if not exist "Dockerfile" (
    call :error "缺少必要的配置文件。请确保当前目录包含docker-compose.yml和Dockerfile文件"
    exit /b 1
)

REM 检查frontend目录是否存在
if not exist "frontend" (
    call :error "找不到frontend目录，请确保项目结构完整"
    exit /b 1
)

REM 预处理Go依赖
if exist "backend\go.mod" (
    call :info "预处理Go模块依赖..."
    
    REM 确保go.sum文件存在
    if not exist "backend\go.sum" (
        echo. > backend\go.sum
    )
    if not exist "go.sum" (
        echo. > go.sum
    )
    
    REM 检查是否已有gorilla/mux依赖
    findstr /C:"github.com/gorilla/mux" backend\go.mod >nul
    if %ERRORLEVEL% neq 0 (
        call :info "添加缺失的gorilla/mux依赖到go.mod..."
        echo require github.com/gorilla/mux v1.8.0 >> backend\go.mod
    )
    
    where go >nul 2>nul
    if %ERRORLEVEL% equ 0 (
        REM 使用本地Go预处理依赖
        pushd backend
        go mod tidy 
        go mod download
        popd
        if %ERRORLEVEL% neq 0 (
            call :warn "本地预处理Go依赖失败，将在Docker中尝试"
        )
    ) else (
        call :warn "未检测到本地Go安装，将在Docker中处理依赖"
    )
)

REM 检查backend/config.json是否存在
if not exist "backend\config.json" (
    call :warn "找不到backend/config.json，将创建默认配置..."
    if not exist "backend" mkdir backend
    (
        echo {
        echo   "host": "0.0.0.0",
        echo   "port": 31457,
        echo   "staticDir": "./static",
        echo   "logLevel": "info",
        echo   "allowedOrigins": "*",
        echo   "dataDir": "../data"
        echo }
    ) > backend\config.json
)

REM 确保部署脚本目录存在
if not exist "deploy\docker" (
    call :info "创建部署脚本目录..."
    mkdir deploy\docker
)

REM 检查并创建启动脚本
call :info "确保启动脚本存在..."
if not exist "deploy\docker\start.sh" (
    call :info "创建启动脚本..."
    if not exist "deploy\docker" mkdir deploy\docker
    
    (
        echo #!/bin/sh
        echo.
        echo # 函数定义
        echo log_info^(\) {
        echo   echo "[INFO] $1"
        echo }
        echo.
        echo log_warn^(\) {
        echo   echo "[WARN] $1"
        echo }
        echo.
        echo log_error^(\) {
        echo   echo "[ERROR] $1"
        echo }
        echo.
        echo log_success^(\) {
        echo   echo "[SUCCESS] $1"
        echo }
        echo.
        echo # 设置错误处理
        echo set -e
        echo.
        echo # 处理信号，实现优雅关闭
        echo trap_handler^(\) {
        echo   log_info "接收到关闭信号，正在停止服务..."
        echo   # 这里可以添加清理操作
        echo   exit 0
        echo }
        echo.
        echo # 注册信号处理器
        echo trap 'trap_handler' INT TERM
        echo.
        echo # 显示容器信息
        echo log_info "===================================="
        echo log_info "    GOSYNFLOOD管理平台启动中..."
        echo log_info "===================================="
        echo log_info "版本: 1.0.0"
        echo log_info "启动时间: $(date)"
        echo log_info "服务端口: 31457"
        echo.
        echo # 更新管理员令牌
        echo if [ ! -z "$ADMIN_TOKEN" ]; then
        echo   sed -i "s/AdminToken = \".*\"/AdminToken = \"$ADMIN_TOKEN\"/g" /app/backend/middleware/auth.go
        echo   log_success "管理员令牌已更新"
        echo else
        echo   log_warn "未设置ADMIN_TOKEN环境变量，使用默认令牌"
        echo fi
        echo.
        echo # 系统检查
        echo log_info "执行系统检查..."
        echo.
        echo # 目录检查
        echo for dir in "/app/bin" "/app/backend" "/app/backend/static" "/app/data"; do
        echo   if [ ! -d "$dir" ]; then
        echo     log_error "错误: 目录不存在: $dir"
        echo     mkdir -p "$dir"
        echo     log_info "已自动创建目录: $dir"
        echo   fi
        echo done
        echo.
        echo # 文件检查
        echo if [ ! -f "/app/bin/attack-server" ]; then
        echo   log_error "错误: 找不到服务器二进制文件: /app/bin/attack-server"
        echo   log_error "请检查构建过程是否正确完成"
        echo   exit 1
        echo fi
        echo.
        echo if [ ! -f "/app/backend/config.json" ]; then
        echo   log_error "错误: 找不到配置文件: /app/backend/config.json"
        echo   mkdir -p /app/backend
        echo   cat ^> /app/backend/config.json ^<^< 'EOL'
        echo {
        echo   "host": "0.0.0.0",
        echo   "port": 31457,
        echo   "staticDir": "./static",
        echo   "logLevel": "info",
        echo   "allowedOrigins": "*",
        echo   "dataDir": "../data"
        echo }
        echo EOL
        echo   log_info "已创建默认配置文件: /app/backend/config.json"
        echo fi
        echo.
        echo if [ ! -f "/app/backend/middleware/auth.go" ]; then
        echo   log_error "错误: 找不到认证中间件: /app/backend/middleware/auth.go"
        echo   log_error "将尝试创建默认认证中间件"
        echo   
        echo   mkdir -p /app/backend/middleware
        echo   cat ^> /app/backend/middleware/auth.go ^<^< 'EOL'
        echo package middleware
        echo.
        echo import (
        echo 	"net/http"
        echo )
        echo.
        echo var (
        echo     AdminToken = "change-me-to-secure-token" 
        echo )
        echo.
        echo // AdminAuthMiddleware 验证管理员令牌
        echo func AdminAuthMiddleware(next http.HandlerFunc) http.HandlerFunc {
        echo 	return func(w http.ResponseWriter, r *http.Request) {
        echo 		token := r.Header.Get("X-Admin-Token")
        echo 		if token != AdminToken {
        echo 			http.Error(w, "未授权访问", http.StatusUnauthorized)
        echo 			return
        echo 		}
        echo 		next(w, r)
        echo 	}
        echo }
        echo EOL
        echo   log_info "已创建默认认证中间件"
        echo fi
        echo.
        echo # 验证静态文件目录
        echo if [ -z "$(ls -A /app/backend/static 2^>/dev/null)" ]; then
        echo   log_warn "警告: 静态文件目录为空，前端可能无法正常工作"
        echo   mkdir -p /app/backend/static
        echo   echo "^<html^>^<body^>^<h1^>GOSYNFLOOD管理平台^</h1^>^<p^>警告: 前端文件缺失，请检查构建过程。^</p^>^</body^>^</html^>" ^> /app/backend/static/index.html
        echo   log_info "已创建临时前端页面"
        echo fi
        echo.
        echo # 验证数据目录权限
        echo if [ ! -w "/app/data" ]; then
        echo   log_error "错误: 数据目录没有写入权限: /app/data"
        echo   chmod 755 /app/data
        echo   log_info "已尝试修复数据目录权限"
        echo fi
        echo.
        echo # 记录环境信息
        echo log_info "系统检查完成"
        echo log_info "环境信息:"
        echo log_info "Alpine版本: $(cat /etc/alpine-release 2^>/dev/null || echo '未知')"
        echo log_info "可用内存: $(free -m 2^>/dev/null | grep Mem | awk '{print $2}' || echo '未知') MB"
        echo log_info "可用磁盘空间: $(df -h / 2^>/dev/null | tail -1 | awk '{print $4}' || echo '未知')"
        echo.
        echo # 启动服务器
        echo log_success "所有检查通过，正在启动服务器..."
        echo cd /app
        echo exec /app/bin/attack-server -config /app/backend/config.json
    ) > deploy\docker\start.sh
    
    REM 确保脚本使用Unix风格的换行符(LF)，并有正确的执行权限
    call :info "已创建启动脚本，将在Docker中正确执行"
    
    REM 使用Docker容器转换换行符为Unix格式并设置执行权限
    where docker >nul 2>nul
    if %ERRORLEVEL% equ 0 (
        docker run --rm -v %cd%/deploy/docker:/scripts alpine:latest /bin/sh -c "sed -i 's/\r$//' /scripts/start.sh && chmod +x /scripts/start.sh" 2>nul
        if %ERRORLEVEL% equ 0 (
            call :success "已优化启动脚本格式和权限"
        ) else (
            call :warn "无法自动优化脚本格式，但不影响基本功能"
        )
    )
)

REM 更新docker-compose.yml以使用新端口
if exist "docker-compose.yml" (
    call :info "检查docker-compose.yml端口配置..."
    REM 读取现有端口配置
    findstr /C:"31458:31457" docker-compose.yml >nul
    if %ERRORLEVEL% equ 0 (
        call :info "使用更新的端口映射: 31458:31457"
        set "PORT_INFO=31458"
    ) else (
        findstr /C:"31457:31457" docker-compose.yml >nul
        if %ERRORLEVEL% equ 0 (
            call :info "使用默认端口映射: 31457:31457"
            set "PORT_INFO=31457"
        ) else (
            call :warn "无法确定端口映射，假设使用31457"
            set "PORT_INFO=31457"
        )
    )
)

REM 确保backend/static目录存在
if not exist "backend\static" (
    mkdir backend\static
)

REM 检查前端文件
call :info "检查前端文件状态..."
dir frontend\dist 2>nul >nul
if %ERRORLEVEL% equ 0 (
    call :info "检测到前端构建产物，确保它们被正确复制"
    if exist "frontend\dist\index.html" (
        call :info "复制前端构建产物到backend/static目录"
        xcopy /E /Y frontend\dist\* backend\static\ >nul
    )
) else (
    call :warn "未检测到前端构建产物，Docker构建将处理这个问题"
)

REM 开始构建
call :info "开始构建Docker镜像（这可能需要几分钟）..."
set ADMIN_TOKEN=%ADMIN_TOKEN%
docker-compose build --no-cache
if %ERRORLEVEL% neq 0 (
    call :error "构建失败，请检查错误信息"
    
    REM 检查是否是Go依赖问题
    for /f "tokens=*" %%a in ('docker-compose logs 2^>^&1 ^| findstr "missing go.sum entry"') do (
        set "GO_ERROR=%%a"
    )
    
    if defined GO_ERROR (
        call :warn "检测到Go依赖问题，尝试修复..."
        where go >nul 2>nul
        if %ERRORLEVEL% equ 0 (
            call :info "运行: cd backend && go mod download github.com/gorilla/mux && go mod tidy"
            pushd backend
            go mod download github.com/gorilla/mux
            go mod tidy
            popd
            call :info "重新尝试构建..."
            docker-compose build --no-cache
            if %ERRORLEVEL% neq 0 (
                call :error "自动修复失败，请手动修复Go依赖问题"
                exit /b 1
            )
        ) else (
            call :error "修复Go依赖问题需要本地安装Go，请手动安装并运行: cd backend && go mod download github.com/gorilla/mux && go mod tidy"
            exit /b 1
        )
    )
    
    exit /b 1
)

REM 检查端口是否被占用
call :info "检查端口占用情况..."
set "PORT_OCCUPIED=0"
for /f "tokens=*" %%a in ('netstat -ano ^| findstr "0.0.0.0:%PORT_INFO%"') do (
    set "PORT_OCCUPIED=1"
)

if "%PORT_OCCUPIED%"=="1" (
    call :warn "端口 %PORT_INFO% 已被占用，将尝试使用备用端口31459"
    
    REM 使用sed替换端口(Windows环境可能需要安装sed)
    where sed >nul 2>nul
    if %ERRORLEVEL% equ 0 (
        sed -i "s/%PORT_INFO%:31457/31459:31457/g" docker-compose.yml
        if %ERRORLEVEL% equ 0 (
            call :info "端口已更新为31459"
            set "PORT_INFO=31459"
        ) else (
            call :warn "无法自动更新端口，请手动编辑docker-compose.yml文件"
        )
    ) else (
        call :warn "未找到sed工具，无法自动更新端口配置，请手动编辑docker-compose.yml文件"
    )
)

REM 启动容器
call :info "构建成功，正在启动容器..."
set ADMIN_TOKEN=%ADMIN_TOKEN%
docker-compose up -d
if %ERRORLEVEL% neq 0 (
    call :error "启动失败，请检查错误信息"
    exit /b 1
)

REM 等待几秒钟让容器完全启动
timeout /t 5 /nobreak >nul

REM 检查容器状态
for /f "tokens=*" %%a in ('docker ps -f "name=gosynflood-manager" --format "{{.Status}}"') do (
    set "CONTAINER_STATUS=%%a"
)

if not defined CONTAINER_STATUS (
    call :error "容器未启动，请使用'docker logs gosynflood-manager'检查详细日志"
    exit /b 1
)

REM 检查容器状态中是否包含"Up"
echo %CONTAINER_STATUS% | findstr /C:"Up" >nul
if %ERRORLEVEL% equ 0 (
    call :success "容器已成功启动！"
    call :success "管理平台地址: http://localhost:%PORT_INFO%"
    call :success "管理员令牌: %ADMIN_TOKEN%"
) else (
    call :error "容器可能未正确启动，请使用'docker logs gosynflood-manager'检查详细日志"
    exit /b 1
)

REM 提供常用命令提示
echo.
call :info "以下是一些有用的命令:"
echo 查看容器日志: docker logs gosynflood-manager
echo 停止服务: docker-compose down
echo 重启服务: docker-compose restart
echo 重建镜像: docker-compose build --no-cache ^&^& docker-compose up -d
echo.

REM 验证令牌设置
call :info "验证认证令牌设置..."
timeout /t 3 /nobreak >nul

REM 检查令牌是否正确设置
for /f "tokens=*" %%a in ('docker exec gosynflood-manager grep -o "AdminToken = \"[^\"]*\"" /app/backend/middleware/auth.go 2^>nul') do (
    set "TOKEN_VALUE=%%a"
)

echo %TOKEN_VALUE% | findstr /C:"%ADMIN_TOKEN%" >nul
if %ERRORLEVEL% equ 0 (
    call :success "认证令牌已正确设置: %TOKEN_VALUE%"
) else (
    call :warn "认证令牌可能未正确设置。实际值: %TOKEN_VALUE%"
    call :warn "如果登录失败，请使用以下命令修复令牌:"
    echo docker exec gosynflood-manager powershell -Command "$content = 'package middleware

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
    AdminToken = \"%ADMIN_TOKEN%\" // 生产环境应使用环境变量
)'; Set-Content -Path '/tmp/header.txt' -Value $content; Get-Content '/app/backend/middleware/auth.go' | Select-String -Pattern 'func AdminAuthMiddleware' -Context 0,1000 | ForEach-Object { $_.Context.PostContext } | Set-Content -Path '/tmp/body.txt'; Get-Content '/tmp/header.txt','/tmp/body.txt' | Set-Content -Path '/app/backend/middleware/auth.go'"
    echo docker restart gosynflood-manager
)

echo.

exit /b 0 