#!/bin/bash

# GOSYNFLOOD-UNION 攻击管理平台一键部署脚本
# 交互式安装向导

set -e

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
    
    # 检查 Go
    if ! command -v go &> /dev/null; then
        print_red "错误: Go 未安装。请安装 Go 1.15 或更高版本。"
        exit 1
    fi
    
    if [ "$INSTALL_MODE" = "manager" ]; then
        # 仅在管理服务器模式下检查 Node.js 和 npm
        if [ "$BUILD_FRONTEND" = true ] && ! command -v node &> /dev/null; then
            print_red "错误: Node.js 未安装。请安装 Node.js 14 或更高版本。"
            exit 1
        fi
        
        if [ "$BUILD_FRONTEND" = true ] && ! command -v npm &> /dev/null; then
            print_red "错误: npm 未安装。请安装 npm。"
            exit 1
        fi
    fi
    
    print_green "依赖检查完成。"
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
        
        # 安装依赖
        npm install
        
        # 构建生产版本
        npm run build
        
        # 复制到静态目录
        mkdir -p "$INSTALL_DIR/backend/static"
        cp -r dist/* "$INSTALL_DIR/backend/static/"
        
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
        
        # 获取依赖
        go mod tidy
        
        # 构建服务器
        go build -o "$INSTALL_DIR/bin/attack-server" main.go
        
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
        
        # 更新管理员令牌
        AUTH_FILE="$INSTALL_DIR/backend/middleware/auth.go"
        if [ -f "$AUTH_FILE" ] && [ ! -z "$ADMIN_TOKEN" ]; then
            echo "更新管理员令牌..."
            sed -i "s/AdminToken = \".*\"/AdminToken = \"$ADMIN_TOKEN\"/g" "$AUTH_FILE"
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
show_welcome
get_install_dir
select_install_mode

if [ "$INSTALL_MODE" = "manager" ]; then
    configure_manager
else
    configure_agent
fi

confirm_installation
check_dependencies
get_source_code

if [ "$INSTALL_MODE" = "manager" ]; then
    build_frontend
    build_backend
    [ "$BUILD_CLIENT" = true ] && build_client
else
    build_client
fi

create_config
show_usage 