#!/bin/bash

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$INSTALL_DIR/backend/config.json"
LOG_FILE="$INSTALL_DIR/logs/server.log"

# 确保日志目录存在
mkdir -p "$INSTALL_DIR/logs"
mkdir -p "$INSTALL_DIR/bin"

# 显示帮助信息
show_help() {
    echo "GOSYNFLOOD-UNION 管理服务器启动脚本"
    echo
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -c, --config <文件>    使用指定的配置文件"
    echo "  -h, --help             显示此帮助信息"
    echo "  -f, --foreground       在前台运行（不在后台运行）"
    echo "  -s, --status           检查服务器状态"
    echo "  -k, --kill             停止正在运行的服务器"
    echo
}

# 获取服务器进程ID
get_server_pid() {
    pgrep -f "attack-server -config"
}

# 检查服务器状态
check_status() {
    PID=$(get_server_pid)
    if [ -z "$PID" ]; then
        echo "管理服务器未运行"
        return 1
    else
        echo "管理服务器正在运行 (PID: $PID)"
        return 0
    fi
}

# 停止服务器
stop_server() {
    PID=$(get_server_pid)
    if [ -z "$PID" ]; then
        echo "管理服务器未运行"
        return 0
    else
        echo "正在停止管理服务器 (PID: $PID)..."
        kill "$PID"
        sleep 2
        if kill -0 "$PID" 2>/dev/null; then
            echo "服务器未响应，强制终止中..."
            kill -9 "$PID"
        fi
        echo "管理服务器已停止"
        return 0
    fi
}

# 默认参数
RUN_IN_BACKGROUND=true

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--foreground)
            RUN_IN_BACKGROUND=false
            shift
            ;;
        -s|--status)
            check_status
            exit $?
            ;;
        -k|--kill)
            stop_server
            exit $?
            ;;
        *)
            echo "错误: 未知选项 $1"
            show_help
            exit 1
            ;;
    esac
done

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件 $CONFIG_FILE 不存在"
    exit 1
fi

# 检查二进制文件是否存在
if [ ! -f "$INSTALL_DIR/bin/attack-server" ]; then
    echo "错误: 服务器二进制文件不存在。请确保已构建项目。"
    exit 1
fi

# 检查服务器是否已在运行
if check_status > /dev/null; then
    echo "管理服务器已经在运行中"
    echo "如需重新启动，请先停止现有服务器："
    echo "$0 --kill"
    exit 1
fi

# 启动服务器
if [ "$RUN_IN_BACKGROUND" = true ]; then
    echo "正在后台启动管理服务器..."
    nohup "$INSTALL_DIR/bin/attack-server" -config "$CONFIG_FILE" > "$LOG_FILE" 2>&1 &
    PID=$!
    echo "管理服务器已启动 (PID: $PID)"
    echo "日志文件: $LOG_FILE"
    # 等待一会，确认服务器正常启动
    sleep 2
    if ! kill -0 $PID 2>/dev/null; then
        echo "警告: 服务器可能未能正常启动，请检查日志文件"
    else
        echo "服务器已成功启动，可以通过以下地址访问："
        # 获取服务器地址和端口
        HOST=$(grep -o '"host": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
        PORT=$(grep -o '"port": *[0-9]*' "$CONFIG_FILE" | awk '{print $2}')
        if [ "$HOST" = "0.0.0.0" ]; then
            # 显示所有IP地址
            echo "本地访问: http://localhost:$PORT"
            echo "远程访问:"
            ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print "  http://" $2}' | cut -d'/' -f1 | awk -v port="$PORT" '{print $0 ":" port}'
        else
            echo "http://$HOST:$PORT"
        fi
    fi
else
    echo "正在前台启动管理服务器..."
    "$INSTALL_DIR/bin/attack-server" -config "$CONFIG_FILE"
fi 