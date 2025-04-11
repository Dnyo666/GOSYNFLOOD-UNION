@echo off
setlocal enabledelayedexpansion

:: 获取脚本所在目录
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "INSTALL_DIR=%SCRIPT_DIR%\.."
set "CONFIG_FILE=%INSTALL_DIR%\backend\config.json"
set "LOG_FILE=%INSTALL_DIR%\logs\server.log"

:: 确保日志目录存在
if not exist "%INSTALL_DIR%\logs" mkdir "%INSTALL_DIR%\logs"
if not exist "%INSTALL_DIR%\bin" mkdir "%INSTALL_DIR%\bin"

:: 命令行参数处理
set "RUN_IN_BACKGROUND=true"
set "SHOW_HELP=false"
set "CHECK_STATUS=false"
set "KILL_SERVER=false"

:parse_args
if "%~1"=="" goto :args_done
if /i "%~1"=="--help" set "SHOW_HELP=true" & goto :args_done
if /i "%~1"=="-h" set "SHOW_HELP=true" & goto :args_done
if /i "%~1"=="--foreground" set "RUN_IN_BACKGROUND=false" & shift & goto :parse_args
if /i "%~1"=="-f" set "RUN_IN_BACKGROUND=false" & shift & goto :parse_args
if /i "%~1"=="--status" set "CHECK_STATUS=true" & goto :args_done
if /i "%~1"=="-s" set "CHECK_STATUS=true" & goto :args_done
if /i "%~1"=="--kill" set "KILL_SERVER=true" & goto :args_done
if /i "%~1"=="-k" set "KILL_SERVER=true" & goto :args_done
if /i "%~1"=="--config" set "CONFIG_FILE=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="-c" set "CONFIG_FILE=%~2" & shift & shift & goto :parse_args
echo 未知选项: %~1
goto :show_help
:args_done

:: 显示帮助信息
if "%SHOW_HELP%"=="true" goto :show_help

:: 配置文件检查
if not exist "%CONFIG_FILE%" (
    echo 错误: 配置文件 %CONFIG_FILE% 不存在
    exit /b 1
)

:: 检查二进制文件是否存在
if not exist "%INSTALL_DIR%\bin\attack-server.exe" (
    echo 错误: 服务器二进制文件不存在。请确保已构建项目。
    exit /b 1
)

:: 查看服务器状态
if "%CHECK_STATUS%"=="true" (
    goto :check_status
)

:: 停止服务器
if "%KILL_SERVER%"=="true" (
    goto :stop_server
)

:: 检查服务器是否已在运行
for /f "tokens=1" %%p in ('wmic process where "commandline like '%%attack-server%%'" get processid ^| findstr /r "[0-9]"') do (
    set "PID=%%p"
    goto :server_running
)
goto :start_server

:server_running
echo 管理服务器已经在运行中 (PID: !PID!)
echo 如需重新启动，请先停止现有服务器：
echo %~nx0 --kill
exit /b 1

:start_server
:: 启动服务器
if "%RUN_IN_BACKGROUND%"=="true" (
    echo 正在后台启动管理服务器...
    start /b cmd /c ""%INSTALL_DIR%\bin\attack-server.exe" -config "%CONFIG_FILE%" > "%LOG_FILE%" 2>&1"
    
    :: 等待一会确认服务器启动
    timeout /t 2 > nul
    
    :: 显示访问信息
    for /f "tokens=* usebackq" %%a in (`type "%CONFIG_FILE%" ^| findstr "host"`) do set "HOST_LINE=%%a"
    for /f "tokens=* usebackq" %%a in (`type "%CONFIG_FILE%" ^| findstr "port"`) do set "PORT_LINE=%%a"
    
    for /f "tokens=2 delims=:," %%a in ("!HOST_LINE!") do set "HOST=%%a"
    set "HOST=!HOST:"=!"
    set "HOST=!HOST: =!"
    
    for /f "tokens=2 delims=:," %%a in ("!PORT_LINE!") do set "PORT=%%a"
    
    echo 服务器已启动！
    echo 日志文件: %LOG_FILE%
    echo.
    echo 服务器可通过以下地址访问:
    echo 本地访问: http://localhost:!PORT!
    
    if "!HOST!"=="0.0.0.0" (
        echo 远程访问:
        for /f "tokens=2 delims=:" %%i in ('ipconfig ^| findstr /r /c:"IPv4 Address"') do (
            echo   http://%%i:!PORT!
        )
    ) else (
        echo http://!HOST!:!PORT!
    )
) else (
    echo 正在前台启动管理服务器...
    "%INSTALL_DIR%\bin\attack-server.exe" -config "%CONFIG_FILE%"
)

exit /b 0

:check_status
:: 检查服务器状态
set "SERVER_RUNNING=false"
for /f "tokens=1" %%p in ('wmic process where "commandline like '%%attack-server%%'" get processid ^| findstr /r "[0-9]"') do (
    set "PID=%%p"
    set "SERVER_RUNNING=true"
)

if "%SERVER_RUNNING%"=="true" (
    echo 管理服务器正在运行 (PID: !PID!)
    exit /b 0
) else (
    echo 管理服务器未运行
    exit /b 1
)

:stop_server
:: 停止服务器
set "SERVER_RUNNING=false"
for /f "tokens=1" %%p in ('wmic process where "commandline like '%%attack-server%%'" get processid ^| findstr /r "[0-9]"') do (
    set "PID=%%p"
    set "SERVER_RUNNING=true"
)

if "%SERVER_RUNNING%"=="true" (
    echo 正在停止管理服务器 (PID: !PID!)...
    taskkill /pid !PID! /f
    echo 管理服务器已停止
) else (
    echo 管理服务器未运行
)
exit /b 0

:show_help
echo GOSYNFLOOD-UNION 管理服务器启动脚本
echo.
echo 用法: %~nx0 [选项]
echo.
echo 选项:
echo   -c, --config ^<文件^>    使用指定的配置文件
echo   -h, --help             显示此帮助信息
echo   -f, --foreground       在前台运行（不在后台运行）
echo   -s, --status           检查服务器状态
echo   -k, --kill             停止正在运行的服务器
echo.
exit /b 0 