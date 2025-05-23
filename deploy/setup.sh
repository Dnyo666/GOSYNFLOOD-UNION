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
    
    # 检查Go是否安装
    if ! command -v go &> /dev/null; then
        print_yellow "未检测到Go，将尝试自动安装Go..."
        if [ "$INTERACTIVE" = true ]; then
            read -p "是否自动安装Go？[Y/n]: " auto_install_go
            if [[ "$auto_install_go" =~ ^[Nn]$ ]]; then
                print_red "错误: Go未安装，安装已取消"
                exit 1
            fi
        fi
        install_go
        
        # 确保Go命令可用
        if ! command -v go &> /dev/null; then
            print_red "Go安装后仍然无法使用，可能是PATH环境变量未正确更新"
            print_yellow "请手动运行: export PATH=\$PATH:/usr/local/go/bin"
            export PATH=$PATH:/usr/local/go/bin
        fi
    fi
    
    # 获取Go版本
    GO_VERSION=$(go version | grep -o 'go[0-9]\+\.[0-9]\+\(\.[0-9]\+\)*' | cut -c 3-)
    GO_MAJOR=$(echo $GO_VERSION | cut -d. -f1)
    GO_MINOR=$(echo $GO_VERSION | cut -d. -f2)
    
    echo "已安装Go $GO_VERSION"
    
    # 检查Go版本是否满足需求
    if [ "$GO_MAJOR" -lt 1 ] || ([ "$GO_MAJOR" -eq 1 ] && [ "$GO_MINOR" -lt 15 ]); then
        print_red "错误: Go版本过低，需要1.15及以上版本"
        if [ "$INTERACTIVE" = true ]; then
            read -p "是否安装新版本Go？[Y/n]: " update_go
            if [[ "$update_go" =~ ^[Nn]$ ]]; then
                exit 1
            else
                install_go
                # 重新获取Go版本
                GO_VERSION=$(go version | grep -o 'go[0-9]\+\.[0-9]\+\(\.[0-9]\+\)*' | cut -c 3-)
                print_green "已更新至Go $GO_VERSION"
            fi
        else
            exit 1
        fi
    fi
    
    # 如果Go版本低于1.18，但高于或等于1.15，自动修改go.mod文件
    if [ "$GO_MAJOR" -eq 1 ] && [ "$GO_MINOR" -lt 18 ]; then
        echo "检测到Go版本低于1.18，将自动修改go.mod文件以兼容当前版本..."
        
        # 修改主go.mod文件
        if [ -f "go.mod" ]; then
            sed -i 's/go 1.18/go 1.15/' go.mod
            echo "已更新 go.mod"
        fi
        
        # 修改backend的go.mod文件
        if [ -f "backend/go.mod" ]; then
            sed -i 's/go 1.18/go 1.15/' backend/go.mod
            echo "已更新 backend/go.mod"
        fi
        
        # 修改client的go.mod文件
        if [ -f "client/go.mod" ]; then
            sed -i 's/go 1.18/go 1.15/' client/go.mod
            echo "已更新 client/go.mod"
        fi
    fi

    # 检查Node.js (仅在manager模式和BUILD_FRONTEND为true时)
    if [ "$INSTALL_MODE" = "manager" ] && [ "$BUILD_FRONTEND" = true ]; then
        check_nodejs
    fi
    
    echo "依赖检查完成。"
}

# 检查Node.js和npm
check_nodejs() {
    if ! command -v node &> /dev/null; then
        print_yellow "未检测到Node.js，前端构建需要Node.js环境"
        
        if [ "$INTERACTIVE" = true ]; then
            read -p "是否尝试安装Node.js？[Y/n]: " install_nodejs_choice
            if [[ "$install_nodejs_choice" =~ ^[Nn]$ ]]; then
                read -p "是否继续安装（跳过前端构建）？[Y/n]: " skip_frontend
                if [[ "$skip_frontend" =~ ^[Nn]$ ]]; then
                    exit 1
                else
                    BUILD_FRONTEND=false
                    print_yellow "已将BUILD_FRONTEND设置为false，将跳过前端构建"
                    return 0
                fi
            else
                install_nodejs
            fi
        else
            print_red "未检测到Node.js，无法构建前端"
            BUILD_FRONTEND=false
            print_yellow "已将BUILD_FRONTEND设置为false，将跳过前端构建"
            return 0
        fi
    fi
    
    # 检查npm
    if ! command -v npm &> /dev/null; then
        print_yellow "检测到Node.js但未检测到npm，尝试安装npm..."
        install_nodejs
    fi
    
    # 验证Node.js和npm版本
    NODE_VERSION=$(node -v | cut -c 2-)
    NPM_VERSION=$(npm -v)
    
    NODE_MAJOR=$(echo $NODE_VERSION | cut -d. -f1)
    
    echo "已安装Node.js $NODE_VERSION 和 npm $NPM_VERSION"
    
    # 检查Node.js版本是否符合要求
    if [ "$NODE_MAJOR" -lt 12 ]; then
        print_yellow "警告: Node.js版本较低 (v$NODE_VERSION)，推荐使用v12或更高版本"
        if [ "$INTERACTIVE" = true ]; then
            read -p "是否更新Node.js？[Y/n]: " update_nodejs
            if [[ ! "$update_nodejs" =~ ^[Nn]$ ]]; then
                install_nodejs
                # 重新获取Node.js版本
                NODE_VERSION=$(node -v | cut -c 2-)
                NPM_VERSION=$(npm -v)
                print_green "已更新至Node.js $NODE_VERSION 和 npm $NPM_VERSION"
            fi
        fi
    fi
}

# 安装Node.js和npm
install_nodejs() {
    print_blue "开始安装Node.js..."
    
    # 检测操作系统类型
    OS=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    elif [[ "$(uname)" == "Darwin" ]]; then
        OS="darwin"
    elif [[ "$(uname -s)" == "MINGW"* || "$(uname -s)" == "MSYS"* || "$(uname -s)" == "CYGWIN"* ]]; then
        OS="windows"
    fi
    
    echo "检测到操作系统: $OS"
    
    case $OS in
        debian|ubuntu)
            print_blue "使用apt安装Node.js..."
            curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
            sudo apt-get install -y nodejs
            ;;
            
        rhel|centos|fedora)
            print_blue "使用yum安装Node.js..."
            curl -fsSL https://rpm.nodesource.com/setup_16.x | sudo bash -
            sudo yum install -y nodejs
            ;;
            
        darwin)
            print_blue "使用Homebrew安装Node.js..."
            if command -v brew &> /dev/null; then
                brew install node
            else
                print_yellow "未检测到Homebrew，准备通过NVM安装Node.js..."
                curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
                # 加载NVM
                export NVM_DIR="$HOME/.nvm"
                [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
                nvm install 16
                nvm use 16
            fi
            ;;
            
        windows)
            print_blue "Windows环境请手动安装Node.js..."
            print_yellow "从https://nodejs.org/下载并安装Node.js 16.x LTS版本"
            print_yellow "安装完成后重新运行此脚本"
            exit 1
            ;;
            
        *)
            print_yellow "未能识别的操作系统，尝试使用NVM安装Node.js..."
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
            # 加载NVM
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            nvm install 16
            nvm use 16
            ;;
    esac
    
    # 验证安装
    if command -v node &> /dev/null && command -v npm &> /dev/null; then
        NODE_VERSION=$(node -v)
        NPM_VERSION=$(npm -v)
        print_green "Node.js和npm安装成功: Node.js $NODE_VERSION, npm $NPM_VERSION"
    else
        print_red "Node.js安装未成功完成"
        if [ "$INTERACTIVE" = true ]; then
            read -p "是否继续安装（跳过前端构建）？[Y/n]: " skip_frontend
            if [[ "$skip_frontend" =~ ^[Nn]$ ]]; then
                exit 1
            else
                BUILD_FRONTEND=false
                print_yellow "已将BUILD_FRONTEND设置为false，将跳过前端构建"
            fi
        else
            BUILD_FRONTEND=false
            print_yellow "已将BUILD_FRONTEND设置为false，将跳过前端构建"
        fi
    fi
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
    
    if [ "$OS" = "linux" ]; then
        # Linux安装流程
        GO_DOWNLOAD_URL="https://golang.org/dl/go${GO_VERSION}.${OS}-${ARCH}.tar.gz"
        BACKUP_URLS=(
            "https://golang.google.cn/dl/go${GO_VERSION}.${OS}-${ARCH}.tar.gz"
            "https://gomirrors.org/dl/go/go${GO_VERSION}.${OS}-${ARCH}.tar.gz"
            "https://mirrors.aliyun.com/golang/go${GO_VERSION}.${OS}-${ARCH}.tar.gz"
        )
        
        # 临时目录
        TMP_DIR=$(mktemp -d)
        GO_TAR="$TMP_DIR/go.tar.gz"
        
        echo "下载Go $GO_VERSION ($OS-$ARCH)..."
        
        # 尝试从主URL下载
        download_success=false
        if command -v curl &> /dev/null; then
            curl -L $GO_DOWNLOAD_URL -o $GO_TAR --connect-timeout 10 &> /dev/null && download_success=true
        elif command -v wget &> /dev/null; then
            wget -O $GO_TAR $GO_DOWNLOAD_URL --timeout=10 &> /dev/null && download_success=true
        fi
        
        # 如果主URL下载失败，尝试备用URL
        if [ "$download_success" = false ]; then
            print_yellow "从主URL下载失败，尝试备用镜像..."
            for url in "${BACKUP_URLS[@]}"; do
                print_yellow "尝试从 $url 下载..."
                if command -v curl &> /dev/null; then
                    curl -L $url -o $GO_TAR --connect-timeout 10 &> /dev/null && { download_success=true; break; }
                elif command -v wget &> /dev/null; then
                    wget -O $GO_TAR $url --timeout=10 &> /dev/null && { download_success=true; break; }
                fi
            done
        fi
        
        if [ "$download_success" = false ]; then
            print_red "无法下载Go安装包，请手动安装Go: https://golang.org/dl/"
            rm -rf $TMP_DIR
            exit 1
        fi
        
        # 默认安装目录
        GO_INSTALL_DIR="/usr/local"
        
        # 检查是否有权限写入安装目录
        if [ ! -w "$GO_INSTALL_DIR" ]; then
            print_yellow "需要管理员权限安装Go到 $GO_INSTALL_DIR"
            print_blue "使用sudo安装Go..."
            sudo tar -C $GO_INSTALL_DIR -xzf $GO_TAR
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
    else
        print_red "目前仅支持Linux自动安装Go"
        print_yellow "请访问 https://golang.org/dl/ 手动下载并安装Go"
        exit 1
    fi
}

# 验证管理服务器URL (仅agent模式)
validate_manager_url() {
    if [ "$INSTALL_MODE" = "agent" ] && [ -n "$MANAGER_URL" ]; then
        echo "验证管理服务器URL..."
        
        # 从URL中提取主机和端口
        HOST=$(echo $MANAGER_URL | sed -E 's|^https?://([^/:]+)(:[0-9]+)?.*|\1|')
        PORT=$(echo $MANAGER_URL | grep -o ':[0-9]\+' | cut -c 2-)
        
        # 如果未指定端口，使用默认端口31457
        if [ -z "$PORT" ]; then
            PORT=31457
            # 更新URL，添加默认端口
            if [[ "$MANAGER_URL" == */ ]]; then
                MANAGER_URL="${MANAGER_URL%/}:31457"
            else
                MANAGER_URL="$MANAGER_URL:31457"
            fi
            print_yellow "未指定端口，使用默认管理服务器端口31457: $MANAGER_URL"
        elif [ "$PORT" = "38721" ]; then
            # 如果是前端开发服务器端口，警告并提供修正
            print_red "警告: 端口38721通常是前端开发服务器端口，不是管理服务器API端口"
            print_yellow "管理服务器API通常使用31457端口"
            
            # 询问是否要纠正端口
            if [ "$INTERACTIVE" = true ]; then
                read -p "是否将端口修改为31457? [Y/n] " change_port
                if [[ "$change_port" != "n" && "$change_port" != "N" ]]; then
                    MANAGER_URL=$(echo $MANAGER_URL | sed 's/:38721/:31457/')
                    print_blue "已更新管理服务器URL: $MANAGER_URL"
                fi
            else
                # 在非交互模式下，自动修改端口并显示警告
                MANAGER_URL=$(echo $MANAGER_URL | sed 's/:38721/:31457/')
                print_yellow "已自动将端口修改为31457: $MANAGER_URL"
            fi
        fi
        
        # 尝试连接管理服务器
        echo "尝试连接到管理服务器..."
        if curl -s --connect-timeout 5 "$MANAGER_URL/api/servers" > /dev/null; then
            print_green "管理服务器连接成功！"
        else
            print_red "警告: 无法连接到管理服务器 $MANAGER_URL"
            print_yellow "请确保管理服务器已启动并可访问"
            print_yellow "您可以继续安装，但代理可能无法连接到管理服务器"
            
            if [ "$INTERACTIVE" = true ]; then
                read -p "是否继续安装? [Y/n] " continue_install
                if [[ "$continue_install" = "n" || "$continue_install" = "N" ]]; then
                    exit 1
                fi
            fi
        fi
    fi
}

# 获取项目代码
get_source_code() {
    # 创建必要的目录
    if [ "$INSTALL_MODE" = "manager" ]; then
        mkdir -p bin data backend/static
    else
        mkdir -p bin config
    fi
    
    # 使用当前目录的代码
    echo "正在检查项目结构..."
    
    # 验证是否在gosynflood项目目录中
    if [ ! -d "backend" ] || [ ! -d "client" ]; then
        print_yellow "警告: 未检测到完整的项目结构，这可能不是gosynflood项目目录"
        print_yellow "当前目录: $(pwd)"
        
        # 输出当前目录的文件列表
        echo "目录内容:"
        ls -la
        
        # 询问用户是否继续
        read -p "是否继续安装? (y/n): " CONTINUE
        if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
            print_red "安装已取消"
            exit 1
        fi
    else
        print_green "检测到gosynflood项目结构，继续安装"
    fi
    
    print_green "源代码准备完成。"
}

# 构建前端
build_frontend() {
    if [ "$BUILD_FRONTEND" = true ] && [ "$INSTALL_MODE" = "manager" ]; then
        echo "正在构建前端..."
        
        # 创建构建日志目录
        mkdir -p "$INSTALL_DIR/logs"
        BUILD_LOG="$INSTALL_DIR/logs/frontend-build.log"
        
        # 使用常规构建方式
        build_frontend_normal
    else
        echo "跳过前端构建。"
    fi
}

# 常规方式构建前端
build_frontend_normal() {
    cd "$INSTALL_DIR/frontend"
    
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
  "host": "0.0.0.0",
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
        
        # 转义API密钥中的特殊字符，避免URL编码问题
        AGENT_KEY_ESCAPED=$(echo "$AGENT_KEY" | sed 's/&/\\&/g')
        
        cat > "$START_SCRIPT" << EOF
#!/bin/bash
cd "\$(dirname "\$0")"
# 使用配置文件启动，也支持命令行参数覆盖
./attack-agent -id $AGENT_ID -key "$AGENT_KEY_ESCAPED" -master "$MANAGER_URL" -tools "/usr/local/bin" "\$@"
# 注意：配置文件位于 $INSTALL_DIR/config/agent-config.json
# 如果您需要修改配置，可以编辑该文件
EOF
        chmod +x "$START_SCRIPT"
        echo "启动脚本已创建: $START_SCRIPT"
        
        # 创建代理配置文件
        CONFIG_FILE="$INSTALL_DIR/config/agent-config.json"
        mkdir -p "$(dirname "$CONFIG_FILE")"
        
        # 转义JSON特殊字符
        AGENT_KEY_JSON=$(echo "$AGENT_KEY" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
        
        cat > "$CONFIG_FILE" << EOF
{
    "ServerID": "$AGENT_ID",
    "APIKey": "$AGENT_KEY_JSON",
    "MasterURL": "$MANAGER_URL",
    "ToolsPath": "/usr/local/bin"
}
EOF
        echo "配置文件已创建: $CONFIG_FILE"
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
        echo "  chmod +x $INSTALL_DIR/deploy/server-launcher.sh"
        echo "  $INSTALL_DIR/deploy/server-launcher.sh"
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

# 创建启动脚本
create_launcher_scripts() {
    if [ "$INSTALL_MODE" = "manager" ]; then
        echo "创建服务器启动脚本..."
        
        # 创建Linux启动脚本
        LINUX_LAUNCHER="$INSTALL_DIR/deploy/server-launcher.sh"
        cat > "$LINUX_LAUNCHER" << 'EOF'
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
        
        echo "本地访问: http://localhost:$PORT"
        
        # 始终尝试显示所有可用IP地址
        echo "远程访问:"
        SERVER_IPS=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1')
        if [ -n "$SERVER_IPS" ]; then
            echo "$SERVER_IPS" | while read -r ip; do
                echo "  http://$ip:$PORT"
            done
        else
            # 如果使用ip命令无法获取IP，尝试使用hostname命令
            SERVER_IP=$(hostname -I | awk '{print $1}')
            if [ -n "$SERVER_IP" ]; then
                echo "  http://$SERVER_IP:$PORT"
            else
                echo "  无法获取服务器IP地址，请检查网络配置"
            fi
        fi
    fi
else
    echo "正在前台启动管理服务器..."
    "$INSTALL_DIR/bin/attack-server" -config "$CONFIG_FILE"
fi
EOF
        chmod +x "$LINUX_LAUNCHER"
        
        # 创建Windows启动脚本
        WINDOWS_LAUNCHER="$INSTALL_DIR/deploy/server-launcher.bat"
        cat > "$WINDOWS_LAUNCHER" << 'EOF'
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
    for /f "tokens=* usebackq" %%a in (`type "%CONFIG_FILE%" ^| findstr "port"`) do set "PORT_LINE=%%a"
    
    :: 提取端口
    for /f "tokens=2 delims=:," %%a in ("!PORT_LINE!") do set "PORT=%%a"
    
    echo 服务器已启动！
    echo 日志文件: %LOG_FILE%
    echo.
    echo 服务器可通过以下地址访问:
    echo 本地访问: http://localhost:!PORT!
    
    :: 始终显示可用的IP地址
    echo 远程访问:
    for /f "tokens=2 delims=:" %%i in ('ipconfig ^| findstr /r /c:"IPv4 Address"') do (
        echo   http://%%i:!PORT!
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
EOF
        
        print_green "启动脚本已创建。"
    fi
}

# 函数：安装gosynflood工具
install_gosynflood_tool() {
    if [ "$INSTALL_MODE" = "agent" ]; then
        echo "开始安装gosynflood攻击工具..."
        
        # 检查gosynflood是否已安装
        if command -v gosynflood &> /dev/null; then
            print_green "gosynflood工具已安装: $(which gosynflood)"
            return 0
        fi
        
        # 安装目标目录
        TOOL_INSTALL_DIR="/usr/local/bin"
        if [ ! -d "$TOOL_INSTALL_DIR" ]; then
            print_yellow "创建工具安装目录: $TOOL_INSTALL_DIR"
            if [ "$EUID" -ne 0 ]; then
                print_yellow "需要root权限，尝试使用sudo..."
                sudo mkdir -p "$TOOL_INSTALL_DIR" || {
                    print_red "无法创建目录，请使用sudo运行安装脚本"
                    return 1
                }
            else
                mkdir -p "$TOOL_INSTALL_DIR"
            fi
        fi
        
        # 直接从本地源码构建gosynflood工具
        print_yellow "从本地源码构建gosynflood工具..."
        
        # 检查源文件是否存在
        if [ ! -f "$INSTALL_DIR/gosynflood.go" ]; then
            print_red "找不到gosynflood源码文件: $INSTALL_DIR/gosynflood.go"
            print_yellow "请确保您在gosynflood项目根目录中运行此脚本"
            return 1
        fi
        
        # 创建临时构建目录
        BUILD_DIR=$(mktemp -d)
        print_yellow "创建临时构建目录: $BUILD_DIR"
        
        # 复制所有必要的源文件到构建目录
        cp "$INSTALL_DIR/gosynflood.go" "$BUILD_DIR/"
        cp "$INSTALL_DIR/sendpayloads.go" "$BUILD_DIR/" 2>/dev/null
        cp "$INSTALL_DIR/cbind.go" "$BUILD_DIR/" 2>/dev/null
        
        # 如果存在go.mod，也复制它
        if [ -f "$INSTALL_DIR/go.mod" ]; then
            cp "$INSTALL_DIR/go.mod" "$BUILD_DIR/"
        else
            # 创建一个简单的go.mod文件
            cd "$BUILD_DIR"
            go mod init gosynflood
        fi
        
        # 构建工具
        cd "$BUILD_DIR"
        print_yellow "开始构建gosynflood工具..."
        go mod tidy
        go build -o gosynflood gosynflood.go || {
            print_red "构建失败，尝试包含其他依赖文件..."
            
            # 尝试使用所有.go文件进行构建
            GO_FILES=$(ls *.go 2>/dev/null)
            go build -o gosynflood $GO_FILES || {
                print_red "gosynflood构建失败"
                rm -rf "$BUILD_DIR"
                return 1
            }
        }
        
        print_green "构建成功"
        
        # 安装工具
        print_yellow "安装gosynflood到 $TOOL_INSTALL_DIR/gosynflood"
        if [ "$EUID" -ne 0 ]; then
            print_yellow "需要root权限，尝试使用sudo..."
            sudo cp "$BUILD_DIR/gosynflood" "$TOOL_INSTALL_DIR/gosynflood"
            sudo chmod +x "$TOOL_INSTALL_DIR/gosynflood"
        else
            cp "$BUILD_DIR/gosynflood" "$TOOL_INSTALL_DIR/gosynflood"
            chmod +x "$TOOL_INSTALL_DIR/gosynflood"
        fi
        
        # 清理临时目录
        rm -rf "$BUILD_DIR"
        
        # 验证安装
        if command -v gosynflood &> /dev/null; then
            print_green "gosynflood工具安装成功: $(which gosynflood)"
            return 0
        else
            print_red "gosynflood安装失败，请手动安装"
            return 1
        fi
    fi
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
        validate_manager_url  # 验证管理服务器URL
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
        validate_manager_url  # 验证管理服务器URL
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
create_launcher_scripts
install_gosynflood_tool
show_usage 