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
    where go >nul 2>nul
    if %ERRORLEVEL% equ 0 (
        REM 使用本地Go预处理依赖
        pushd backend
        go mod tidy 
        go mod download github.com/gorilla/mux 
        go mod download
        popd
        if %ERRORLEVEL% neq 0 (
            call :warn "本地预处理Go依赖失败，将在Docker中尝试"
        )
    ) else (
        call :warn "未检测到本地Go安装，将在Docker中处理依赖"
    )
    
    REM 确保go.sum文件存在
    if not exist "backend\go.sum" (
        echo. > backend\go.sum
    )
    if not exist "go.sum" (
        echo. > go.sum
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

REM 确保backend/static目录存在
if not exist "backend\static" (
    mkdir backend\static
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
    call :success "管理平台地址: http://localhost:31457"
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

exit /b 0 