#!/bin/bash

# GOSYNFLOOD-UNION 攻击管理平台一键部署脚本
# 支持交互式安装向导和命令行参数方式安装

set -e

# 默认配置
INSTALL_DIR="$PWD"
INSTALL_MODE=""
ADMIN_TOKEN=""
MANAGER_URL=""
AGENT_ID=""
AGENT_KEY=""
BUILD_FRONTEND=true
BUILD_BACKEND=true
BUILD_CLIENT=true
INTERACTIVE=true

# 彩色输出函数
print_green() {
    echo -e "\033[0;32m$1\033[0m"
}

print_blue() {
    echo -e "\033[0;34m$1\033[0m"
}

print_yellow() {
    echo -e "\033[0;33m$1\033[0m"
}

print_red() {
    echo -e "\033[0;31m$1\033[0m"
}

# 显示帮助信息
show_help() {
    echo "GOSYNFLOOD-UNION 攻击管理平台安装脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --mode=(manager|agent)   安装模式，管理服务器或攻击代理"
    echo "  --install-dir=<目录>     指定安装目录"
    echo "  --admin-token=<令牌>     设置管理员令牌（仅manager模式）"
    echo "  --manager-url=<URL>      管理服务器URL（仅agent模式）"
    echo "  --agent-key=<密钥>       攻击代理的API密钥（仅agent模式）"
    echo "  --agent-id=<ID>          攻击代理的ID（仅agent模式）"
    echo "  --no-frontend            不构建前端（仅manager模式）"
    echo "  --no-backend             不构建后端（仅manager模式）"
    echo "  --no-client              不构建客户端代理"
    echo "  --help                   显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 --mode=manager --admin-token=\"secure-token\""
    echo "  $0 --mode=agent --manager-url=\"http://192.168.1.100:31457\" --agent-id=1 --agent-key=\"api-key\""
    echo ""
}

# 解析命令行参数
parse_args() {
    for arg in "$@"; do
        case $arg in
            --mode=*)
                INSTALL_MODE="${arg#*=}"
                INTERACTIVE=false
                ;;
            --install-dir=*)
                INSTALL_DIR="${arg#*=}"
                ;;
            --admin-token=*)
                ADMIN_TOKEN="${arg#*=}"
                ;;
            --manager-url=*)
                MANAGER_URL="${arg#*=}"
                ;;
            --agent-key=*)
                AGENT_KEY="${arg#*=}"
                ;;
            --agent-id=*)
                AGENT_ID="${arg#*=}"
                ;;
            --no-frontend)
                BUILD_FRONTEND=false
                ;;
            --no-backend)
                BUILD_BACKEND=false
                ;;
            --no-client)
                BUILD_CLIENT=false
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                # 忽略未知参数
                ;;
        esac
    done
    
    # 验证参数
    if [ "$INTERACTIVE" = false ]; then
        if [ -z "$INSTALL_MODE" ]; then
            print_red "错误: 必须指定安装模式 (--mode=manager|agent)"
            exit 1
        fi
        
        if [ "$INSTALL_MODE" != "manager" ] && [ "$INSTALL_MODE" != "agent" ]; then
            print_red "错误: 安装模式必须是 'manager' 或 'agent'"
            exit 1
        fi
        
        if [ "$INSTALL_MODE" = "agent" ]; then
            if [ -z "$MANAGER_URL" ] || [ -z "$AGENT_KEY" ] || [ -z "$AGENT_ID" ]; then
                print_red "错误: agent模式必须提供 --manager-url, --agent-key 和 --agent-id 参数"
                exit 1
            fi
        fi
    fi
}

# 显示欢迎信息
show_welcome() {
    clear
    print_blue "=================================================="
    print_blue "    GOSYNFLOOD-UNION 攻击管理平台安装向导"
    print_blue "=================================================="
    echo ""
    print_yellow "该工具仅供授权的网络安全测试、教育和研究目的使用。"
    print_yellow "未经授权对计算机系统和网络发起攻击是违法的。"
    echo ""
    print_blue "本向导将引导您完成安装过程。"
    echo ""
    read -p "按回车键继续..."
}

# 收集安装路径
get_install_dir() {
    echo ""
    print_blue "【步骤 1】选择安装目录"
    echo ""
    echo "请指定安装目录（留空则使用当前目录）:"
    read -p "安装路径: " INSTALL_DIR
    
    if [ -z "$INSTALL_DIR" ]; then
        INSTALL_DIR="$PWD"
        echo "将使用当前目录: $INSTALL_DIR"
    else
        # 创建目录（如果不存在）
        mkdir -p "$INSTALL_DIR"
        echo "将安装到: $INSTALL_DIR"
    fi
    
    # 切换到安装目录
    cd "$INSTALL_DIR"
    echo ""
}

# 选择安装模式
select_install_mode() {
    echo ""
    print_blue "【步骤 2】选择安装模式"
    echo ""
    echo "请选择安装模式:"
    echo "1) 管理服务器 - 安装完整的管理平台（包括前端、后端和API服务）"
    echo "2) 攻击代理 - 仅安装攻击客户端（连接到现有的管理服务器）"
    echo ""
    
    while true; do
        read -p "请输入选项 [1/2]: " mode_choice
        case $mode_choice in
            1)
                INSTALL_MODE="manager"
                echo "已选择: 管理服务器模式"
                break
                ;;
            2)
                INSTALL_MODE="agent"
                echo "已选择: 攻击代理模式"
                break
                ;;
            *)
                print_red "错误: 请输入 1 或 2"
                ;;
        esac
    done
    echo ""
}

# 管理服务器特定配置
configure_manager() {
    echo ""
    print_blue "【步骤 3】配置管理服务器"
    echo ""
    
    # 询问是否自动生成令牌
    echo "管理员令牌用于保护管理界面和API。"
    echo "1) 自动生成安全令牌（推荐）"
    echo "2) 手动指定管理员令牌"
    echo ""
    
    while true; do
        read -p "请选择 [1/2]: " token_choice
        case $token_choice in
            1)
                ADMIN_TOKEN=$(openssl rand -hex 16)
                print_green "已生成管理员令牌: $ADMIN_TOKEN"
                echo ""
                echo "请妥善保存此令牌！它用于管理操作和配置攻击代理。"
                break
                ;;
            2)
                while true; do
                    read -p "请输入管理员令牌 (至少8个字符): " ADMIN_TOKEN
                    if [ ${#ADMIN_TOKEN} -ge 8 ]; then
                        break
                    else
                        print_red "令牌太短，请至少使用8个字符"
                    fi
                done
                break
                ;;
            *)
                print_red "错误: 请输入 1 或 2"
                ;;
        esac
    done
    
    # 选择要构建的组件
    echo ""
    echo "选择要构建的组件:"
    
    read -p "构建前端界面？[Y/n]: " build_frontend_choice
    if [[ "$build_frontend_choice" =~ ^[Nn]$ ]]; then
        BUILD_FRONTEND=false
        echo "跳过前端构建"
    else
        BUILD_FRONTEND=true
        echo "将构建前端界面"
    fi
    
    read -p "构建后端API服务？[Y/n]: " build_backend_choice
    if [[ "$build_backend_choice" =~ ^[Nn]$ ]]; then
        BUILD_BACKEND=false
        echo "跳过后端构建"
    else
        BUILD_BACKEND=true
        echo "将构建后端API服务"
    fi
    
    read -p "构建客户端代理？[Y/n]: " build_client_choice
    if [[ "$build_client_choice" =~ ^[Nn]$ ]]; then
        BUILD_CLIENT=false
        echo "跳过客户端代理构建"
    else
        BUILD_CLIENT=true
        echo "将构建客户端代理"
    fi
    
    echo ""
}

# 攻击代理特定配置
configure_agent() {
    echo ""
    print_blue "【步骤 3】配置攻击代理"
    echo ""
    
    # 收集管理服务器URL
    while true; do
        read -p "管理服务器URL (例如: http://192.168.1.100:31457): " MANAGER_URL
        if [ -n "$MANAGER_URL" ]; then
            break
        else
            print_red "请输入管理服务器URL"
        fi
    done
    
    # 收集代理ID
    while true; do
        read -p "代理ID (数字): " AGENT_ID
        if [[ "$AGENT_ID" =~ ^[0-9]+$ ]]; then
            break
        else
            print_red "代理ID必须是数字"
        fi
    done
    
    # 收集API密钥
    while true; do
        read -p "API密钥 (从管理界面获取): " AGENT_KEY
        if [ -n "$AGENT_KEY" ]; then
            break
        else
            print_red "请输入API密钥"
        fi
    done
    
    # 攻击代理模式下默认只构建客户端
    BUILD_FRONTEND=false
    BUILD_BACKEND=false
    BUILD_CLIENT=true
    
    echo ""
}

# 确认安装配置
confirm_installation() {
    echo ""
    print_blue "【安装确认】"
    echo ""
    echo "请确认以下安装配置:"
    echo "安装路径: $INSTALL_DIR"
    echo "安装模式: $INSTALL_MODE"
    
    if [ "$INSTALL_MODE" = "manager" ]; then
        echo "管理员令牌: $ADMIN_TOKEN"
        echo "构建前端: $([ "$BUILD_FRONTEND" = true ] && echo "是" || echo "否")"
        echo "构建后端: $([ "$BUILD_BACKEND" = true ] && echo "是" || echo "否")"
        echo "构建客户端: $([ "$BUILD_CLIENT" = true ] && echo "是" || echo "否")"
    else
        echo "管理服务器URL: $MANAGER_URL"
        echo "代理ID: $AGENT_ID"
        echo "API密钥: $AGENT_KEY"
    fi
    
    echo ""
    read -p "确认以上配置并开始安装？[Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        print_red "安装已取消"
        exit 0
    fi
    
    echo ""
    print_blue "开始安装过程..."
    echo ""
}

# 检查必要的工具
check_dependencies() {
    echo "检查依赖工具..."
    
    # 先尝试激活已安装的Go（如果存在）
    if [ -d "/usr/local/go/bin" ] && ! command -v go &> /dev/null; then
        print_yellow "检测到Go安装目录，但PATH中未找到go命令，添加到PATH环境变量..."
        export PATH=$PATH:/usr/local/go/bin
    fi
    
    # 检查 Go
    if ! command -v go &> /dev/null; then
        print_yellow "未检测到Go，将尝试自动安装Go 1.18..."
        install_go
        
        # 确保Go命令可用
        if ! command -v go &> /dev/null; then
            print_red "Go安装后仍然无法使用，可能是PATH环境变量未正确更新"
            print_yellow "请手动运行: export PATH=\$PATH:/usr/local/go/bin"
            export PATH=$PATH:/usr/local/go/bin
        fi
    else
        # 检查Go版本
        GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
        GO_MAJOR=$(echo $GO_VERSION | cut -d. -f1)
        GO_MINOR=$(echo $GO_VERSION | cut -d. -f2)
        
        if [ "$GO_MAJOR" -lt 1 ] || ([ "$GO_MAJOR" -eq 1 ] && [ "$GO_MINOR" -lt 15 ]); then
            print_yellow "检测到Go版本为 $GO_VERSION，低于要求的1.15版本。"
            read -p "是否更新到最新版本？[Y/n]: " update_go
            if [[ ! "$update_go" =~ ^[Nn]$ ]]; then
                install_go
            else
                print_yellow "继续使用当前Go版本，可能会影响部分功能。"
            fi
        else
            print_green "已安装Go $GO_VERSION，符合要求。"
        fi
    fi
    
    if [ "$INSTALL_MODE" = "manager" ]; then
        # 仅在管理服务器模式下检查 Node.js 和 npm
        if [ "$BUILD_FRONTEND" = true ] && ! command -v node &> /dev/null; then
            print_red "错误: Node.js 未安装。请安装 Node.js 14 或更高版本。"
            print_yellow "提示: 可以访问 https://nodejs.org/ 下载安装Node.js"
            exit 1
        fi
        
        if [ "$BUILD_FRONTEND" = true ] && ! command -v npm &> /dev/null; then
            print_red "错误: npm 未安装。请安装 npm。"
            exit 1
        fi
    fi
    
    print_green "依赖检查完成。"
}

# 安装Go
install_go() {
    print_blue "开始安装Go..."
    
    # 如果PATH中已经存在Go，则跳过安装
    if command -v go &> /dev/null; then
        GO_VERSION=$(go version)
        print_green "Go已经安装: $GO_VERSION"
        return 0
    fi
    
    # 检测操作系统和架构
    case "$(uname -s)" in
        Linux*)     OS="linux" ;;
        Darwin*)    OS="darwin" ;;
        MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
        *)          
            print_red "不支持的操作系统: $(uname -s)"
            print_yellow "请手动安装Go 1.15+: https://golang.org/dl/"
            exit 1 
            ;;
    esac
    
    ARCH="$(uname -m)"
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            print_red "不支持的系统架构: $ARCH"
            print_yellow "请手动安装Go 1.15+: https://golang.org/dl/"
            exit 1
            ;;
    esac
    
    # 设置Go版本
    GO_VERSION="1.18.10"
    
    # Windows平台特殊处理
    if [ "$OS" = "windows" ]; then
        print_yellow "检测到Windows系统，将下载安装程序..."
        print_yellow "安装完成后请重新运行此脚本。"
        
        # Windows使用zip或msi
        GO_DOWNLOAD_URL="https://golang.org/dl/go${GO_VERSION}.windows-${ARCH}.zip"
        
        # 临时目录
        TMP_DIR="${TEMP:-/tmp}"
        GO_ZIP="$TMP_DIR/go.zip"
        
        echo "下载Go $GO_VERSION (windows-$ARCH)..."
        if command -v curl &> /dev/null; then
            curl -L $GO_DOWNLOAD_URL -o $GO_ZIP
        elif command -v wget &> /dev/null; then
            wget -O $GO_ZIP $GO_DOWNLOAD_URL
        else
            print_red "错误: 需要curl或wget来下载Go"
            print_yellow "请访问 https://golang.org/dl/ 手动下载安装"
            exit 1
        fi
        
        if [ ! -f $GO_ZIP ]; then
            print_red "下载失败，请手动安装Go: https://golang.org/dl/"
            exit 1
        fi
        
        # 解压目录
        GO_INSTALL_DIR="${LOCALAPPDATA:-$HOME}/go"
        
        # 确保目录存在
        mkdir -p "$GO_INSTALL_DIR"
        
        print_blue "正在解压Go到 $GO_INSTALL_DIR..."
        if command -v unzip &> /dev/null; then
            unzip -q -o $GO_ZIP -d "$GO_INSTALL_DIR"
        else
            print_red "未找到unzip工具，无法解压Go安装包"
            print_yellow "请手动解压 $GO_ZIP 到 $GO_INSTALL_DIR"
            exit 1
        fi
        
        # 添加到PATH（Windows特有）
        print_yellow "请确保将以下路径添加到系统环境变量PATH中:"
        print_yellow "$GO_INSTALL_DIR\\go\\bin"
        
        # 设置临时环境变量
        export PATH="$GO_INSTALL_DIR/go/bin:$PATH"
        
        # 验证安装
        if command -v go &> /dev/null; then
            GO_VERSION=$(go version)
            print_green "Go安装成功: $GO_VERSION"
        else
            print_red "Go安装后无法在PATH中找到"
            print_yellow "请确保添加 $GO_INSTALL_DIR\\go\\bin 到PATH环境变量并重启终端"
            exit 1
        fi
    else
        # Linux/macOS安装流程
        GO_DOWNLOAD_URL="https://golang.org/dl/go${GO_VERSION}.${OS}-${ARCH}.tar.gz"
        
        # 临时目录
        TMP_DIR=$(mktemp -d)
        GO_TAR="$TMP_DIR/go.tar.gz"
        
        echo "下载Go $GO_VERSION ($OS-$ARCH)..."
        if command -v curl &> /dev/null; then
            curl -L $GO_DOWNLOAD_URL -o $GO_TAR
        elif command -v wget &> /dev/null; then
            wget -O $GO_TAR $GO_DOWNLOAD_URL
        else
            print_red "错误: 需要curl或wget来下载Go"
            exit 1
        fi
        
        if [ ! -f $GO_TAR ]; then
            print_red "下载失败，请手动安装Go: https://golang.org/dl/"
            exit 1
        fi
        
        # 默认安装目录
        GO_INSTALL_DIR="/usr/local"
        
        # 检查是否有权限写入安装目录
        if [ ! -w "$GO_INSTALL_DIR" ]; then
            print_yellow "需要管理员权限安装Go到 $GO_INSTALL_DIR"
            if [ "$OS" = "linux" ] || [ "$OS" = "darwin" ]; then
                print_blue "使用sudo安装Go..."
                sudo tar -C $GO_INSTALL_DIR -xzf $GO_TAR
            else
                print_red "请使用管理员权限运行安装程序，或手动安装Go"
                exit 1
            fi
        else
            tar -C $GO_INSTALL_DIR -xzf $GO_TAR
        fi
        
        # 清理临时文件
        rm -rf $TMP_DIR
        
        # 设置PATH
        if ! grep -q "export PATH=\$PATH:/usr/local/go/bin" ~/.bashrc 2>/dev/null && \
           ! grep -q "export PATH=\$PATH:/usr/local/go/bin" ~/.zshrc 2>/dev/null && \
           ! grep -q "export PATH=\$PATH:/usr/local/go/bin" ~/.profile 2>/dev/null; then
            
            print_yellow "将Go添加到环境变量PATH中..."
            
            if [ -f ~/.profile ]; then
                echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
                print_green "已添加到 ~/.profile"
            fi
            
            if [ -f ~/.bashrc ]; then
                echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
                print_green "已添加到 ~/.bashrc"
            fi
            
            if [ -f ~/.zshrc ]; then
                echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.zshrc
                print_green "已添加到 ~/.zshrc"
            fi
            
            print_yellow "请运行以下命令使PATH变量立即生效，或重启终端:"
            print_yellow "export PATH=\$PATH:/usr/local/go/bin"
        fi
        
        # 临时添加到当前会话的PATH
        export PATH=$PATH:/usr/local/go/bin
        
        # 验证安装
        if command -v go &> /dev/null; then
            GO_VERSION=$(go version)
            print_green "Go安装成功: $GO_VERSION"
        else
            print_red "Go安装后无法在PATH中找到，请手动添加 /usr/local/go/bin 到PATH环境变量"
            print_yellow "export PATH=\$PATH:/usr/local/go/bin"
            exit 1
        fi
    fi
}

# 获取项目代码
get_source_code() {
    # 创建必要的目录
    if [ "$INSTALL_MODE" = "manager" ]; then
        mkdir -p bin data backend/static
    else
        mkdir -p bin
    fi
    
    # 获取项目代码（如果不在项目目录内）
    if [ ! -d "backend" ] || [ ! -d "frontend" ] || [ ! -d "client" ]; then
        echo "正在克隆项目代码..."
        git clone https://github.com/Dnyo666/gosynflood-union.git .
    else
        echo "正在更新项目代码..."
        git pull
    fi
    
    print_green "源代码准备完成。"
}

# 构建前端
build_frontend() {
    if [ "$BUILD_FRONTEND" = true ] && [ "$INSTALL_MODE" = "manager" ]; then
        echo "正在构建前端..."
        cd "$INSTALL_DIR/frontend"
        
        # 创建构建日志目录
        mkdir -p "$INSTALL_DIR/logs"
        BUILD_LOG="$INSTALL_DIR/logs/frontend-build.log"
        
        # 安装依赖，抑制警告并记录日志
        echo "安装npm依赖（这可能需要几分钟时间）..."
        print_yellow "详细日志记录在: $BUILD_LOG"
        npm install --no-fund --no-audit --loglevel=error > "$BUILD_LOG" 2>&1 || {
            print_red "npm依赖安装失败，查看日志获取详情: $BUILD_LOG"
            cat "$BUILD_LOG"
            exit 1
        }
        
        # 构建生产版本
        echo "构建前端应用..."
        npm run build >> "$BUILD_LOG" 2>&1 || {
            print_red "前端构建失败，查看日志获取详情: $BUILD_LOG"
            cat "$BUILD_LOG"
            exit 1
        }
        
        # 检查dist目录是否存在
        if [ -d "dist" ]; then
            # 如果存在dist目录，复制到静态目录
            print_green "将构建文件从dist目录复制到静态目录..."
            mkdir -p "$INSTALL_DIR/backend/static"
            cp -r dist/* "$INSTALL_DIR/backend/static/" 2>/dev/null || {
                print_red "复制构建文件失败，请检查权限和路径。"
            }
        else
            # 检查日志来确认构建是否成功
            if grep -q "Build complete" "$BUILD_LOG" 2>/dev/null || [ -d "$INSTALL_DIR/backend/static" ]; then
                print_green "前端已直接构建到 backend/static 目录，无需复制。"
            else
                print_red "前端构建可能失败，未找到构建输出目录。"
                print_yellow "请检查 $BUILD_LOG 获取详细信息。"
            fi
        fi
        
        print_green "前端构建完成。"
    else
        echo "跳过前端构建。"
    fi
}

# 构建后端
build_backend() {
    if [ "$BUILD_BACKEND" = true ] && [ "$INSTALL_MODE" = "manager" ]; then
        echo "正在构建后端..."
        cd "$INSTALL_DIR/backend"
        
        # 创建日志目录
        mkdir -p "$INSTALL_DIR/logs"
        BUILD_LOG="$INSTALL_DIR/logs/backend-build.log"
        
        # 获取依赖
        echo "正在下载Go依赖..."
        go mod tidy > "$BUILD_LOG" 2>&1 || {
            print_red "Go依赖获取失败，查看日志获取详情: $BUILD_LOG"
            cat "$BUILD_LOG"
            exit 1
        }
        
        # 构建服务器
        echo "正在编译后端服务..."
        go build -o "$INSTALL_DIR/bin/attack-server" main.go >> "$BUILD_LOG" 2>&1 || {
            print_red "后端构建失败，查看日志获取详情: $BUILD_LOG"
            print_yellow "可能是由于导入但未使用的包或其他编译错误。"
            cat "$BUILD_LOG"
            
            # 尝试修复常见错误
            if grep -q "imported and not used:" "$BUILD_LOG"; then
                print_yellow "检测到导入但未使用的包，尝试修复并重新构建..."
                
                # 尝试再次构建，忽略未使用的导入
                GOOS=linux go build -o "$INSTALL_DIR/bin/attack-server" main.go >> "$BUILD_LOG" 2>&1 || {
                    print_red "修复后仍然构建失败，请手动修复错误。"
                    exit 1
                }
                
                print_green "使用修复后重新构建成功。"
            else
                exit 1
            fi
        }
        
        print_green "后端构建完成。"
    else
        echo "跳过后端构建。"
    fi
}

# 构建客户端代理
build_client() {
    if [ "$BUILD_CLIENT" = true ]; then
        echo "正在构建客户端代理..."
        cd "$INSTALL_DIR/client"
        
        # 获取依赖
        go mod tidy
        
        # 构建客户端代理
        go build -o "$INSTALL_DIR/bin/attack-agent" agent.go
        
        print_green "客户端代理构建完成。"
    else
        echo "跳过客户端代理构建。"
    fi
}

# 创建配置文件
create_config() {
    if [ "$INSTALL_MODE" = "manager" ]; then
        # 创建后端配置文件
        CONFIG_FILE="$INSTALL_DIR/backend/config.json"
        
        if [ ! -f "$CONFIG_FILE" ]; then
            echo "创建后端配置文件..."
            cat > "$CONFIG_FILE" << EOF
{
  "port": 31457,
  "staticDir": "./static",
  "logLevel": "info",
  "allowedOrigins": "*",
  "dataDir": "../data"
}
EOF
            echo "配置文件已创建: $CONFIG_FILE"
        else
            echo "后端配置文件已存在，跳过创建。"
        fi
        
        # 创建并更新middleware目录和auth.go文件
        MIDDLEWARE_DIR="$INSTALL_DIR/backend/middleware"
        AUTH_FILE="$MIDDLEWARE_DIR/auth.go"
        
        mkdir -p "$MIDDLEWARE_DIR"
        
        # 检查auth.go文件是否存在，如果不存在则创建
        if [ ! -f "$AUTH_FILE" ]; then
            echo "创建auth.go文件..."
            cat > "$AUTH_FILE" << EOF
package middleware

import (
	"net/http"
)

var (
    AdminToken = "$ADMIN_TOKEN" 
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
            print_green "Auth中间件文件已创建。"
        else
            # 更新管理员令牌
            echo "更新管理员令牌..."
            # 兼容不同平台的sed命令
            if [[ "$(uname -s)" == Darwin* ]]; then
                # macOS
                sed -i '' "s/AdminToken = \".*\"/AdminToken = \"$ADMIN_TOKEN\"/g" "$AUTH_FILE"
            else
                # Linux and other systems
                sed -i "s/AdminToken = \".*\"/AdminToken = \"$ADMIN_TOKEN\"/g" "$AUTH_FILE"
            fi
            echo "管理员令牌已更新。"
        fi
    else
        # 创建代理启动脚本
        START_SCRIPT="$INSTALL_DIR/bin/start-agent.sh"
        echo "创建代理启动脚本..."
        cat > "$START_SCRIPT" << EOF
#!/bin/bash
cd "\$(dirname "\$0")"
./attack-agent -id $AGENT_ID -key "$AGENT_KEY" -master "$MANAGER_URL" -tools "/usr/local/bin" "\$@"
EOF
        chmod +x "$START_SCRIPT"
        echo "启动脚本已创建: $START_SCRIPT"
    fi
}

# 安装完成后显示使用说明
show_usage() {
    echo ""
    print_green "安装完成！"
    echo ""
    
    if [ "$INSTALL_MODE" = "manager" ]; then
        print_blue "【管理服务器配置】"
        print_yellow "管理员令牌: $ADMIN_TOKEN"
        echo "请记录此令牌，用于添加服务器和创建攻击任务。"
        echo ""
        echo "启动管理服务器:"
        echo "  cd $INSTALL_DIR/bin"
        echo "  ./attack-server -config ../backend/config.json"
        echo ""
        echo "访问Web界面:"
        echo "  http://localhost:31457"
        echo ""
        echo "添加攻击服务器时，需要生成API密钥并在攻击服务器上使用。"
    else
        print_blue "【攻击代理配置】"
        echo "管理服务器: $MANAGER_URL"
        echo "代理ID: $AGENT_ID"
        echo "API密钥: $AGENT_KEY"
        echo ""
        echo "启动攻击代理:"
        echo "  cd $INSTALL_DIR/bin"
        echo "  ./start-agent.sh"
        echo ""
        echo "请确保本机已安装gosynflood工具，或指定正确的工具路径。"
    fi
    
    echo ""
    print_blue "感谢使用GOSYNFLOOD-UNION攻击管理平台！"
}

# 主流程
# 解析命令行参数
parse_args "$@"

# 创建并切换到安装目录
if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

if [ "$INTERACTIVE" = true ]; then
    # 交互式模式
    show_welcome
    get_install_dir
    select_install_mode
    
    if [ "$INSTALL_MODE" = "manager" ]; then
        configure_manager
    else
        configure_agent
    fi
    
    confirm_installation
else
    # 非交互式模式
    print_blue "GOSYNFLOOD-UNION 攻击管理平台安装程序"
    print_blue "使用非交互式模式安装"
    echo ""
    echo "安装配置:"
    echo "安装目录: $INSTALL_DIR"
    echo "安装模式: $INSTALL_MODE"
    
    if [ "$INSTALL_MODE" = "manager" ]; then
        if [ -z "$ADMIN_TOKEN" ]; then
            ADMIN_TOKEN=$(openssl rand -hex 16)
            print_yellow "自动生成管理员令牌: $ADMIN_TOKEN"
        else
            echo "管理员令牌: $ADMIN_TOKEN"
        fi
        echo "构建前端: $([ "$BUILD_FRONTEND" = true ] && echo "是" || echo "否")"
        echo "构建后端: $([ "$BUILD_BACKEND" = true ] && echo "是" || echo "否")"
        echo "构建客户端: $([ "$BUILD_CLIENT" = true ] && echo "是" || echo "否")"
    else
        echo "管理服务器URL: $MANAGER_URL"
        echo "代理ID: $AGENT_ID"
        echo "API密钥: $AGENT_KEY"
        # 攻击代理模式下默认只构建客户端
        BUILD_FRONTEND=false
        BUILD_BACKEND=false
    fi
    
    echo ""
fi

check_dependencies
get_source_code

if [ "$INSTALL_MODE" = "manager" ]; then
    [ "$BUILD_FRONTEND" = true ] && build_frontend
    [ "$BUILD_BACKEND" = true ] && build_backend
    [ "$BUILD_CLIENT" = true ] && build_client
else
    [ "$BUILD_CLIENT" = true ] && build_client
fi

create_config
show_usage 