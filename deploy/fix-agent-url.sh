#!/bin/bash

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 输出函数
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

info "开始修复攻击代理URL问题..."

# 查找代理配置文件
config_paths=(
    "./config/agent-config.json"
    "../config/agent-config.json"
    "./agent-config.json"
    "/etc/gosynflood/agent-config.json"
    "$HOME/gosynflood/config/agent-config.json"
)

CONFIG_FILE=""
for path in "${config_paths[@]}"; do
    if [ -f "$path" ]; then
        CONFIG_FILE="$path"
        break
    fi
done

if [ -z "$CONFIG_FILE" ]; then
    warn "找不到配置文件，请指定配置文件路径:"
    read -p "配置文件路径: " CONFIG_FILE
    
    if [ ! -f "$CONFIG_FILE" ]; then
        error "指定的配置文件不存在: $CONFIG_FILE"
        exit 1
    fi
fi

info "找到配置文件: $CONFIG_FILE"

# 备份配置文件
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
success "已创建配置文件备份: ${CONFIG_FILE}.bak"

# 分析URL格式
MASTER_URL=$(grep -o '"masterUrl"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)

if [ -z "$MASTER_URL" ]; then
    error "无法从配置文件中提取masterUrl"
    exit 1
fi

info "当前masterUrl值: $MASTER_URL"

# 修复URL格式问题
FIXED_URL="$MASTER_URL"

# 1. 添加协议前缀
if [[ ! "$FIXED_URL" =~ ^https?:// ]]; then
    FIXED_URL="http://$FIXED_URL"
    warn "URL缺少协议前缀，已添加http://"
fi

# 2. 修复常见的协议格式错误
if [[ "$FIXED_URL" =~ ^http:/ ]] && [[ ! "$FIXED_URL" =~ ^http:// ]]; then
    FIXED_URL="${FIXED_URL/http:\/http:\/\/}"
    warn "修复了HTTP协议格式"
fi

if [[ "$FIXED_URL" =~ ^https:/ ]] && [[ ! "$FIXED_URL" =~ ^https:// ]]; then
    FIXED_URL="${FIXED_URL/https:\/https:\/\/}"
    warn "修复了HTTPS协议格式"
fi

# 3. 移除末尾的斜杠
FIXED_URL="${FIXED_URL%/}"

# 如果URL已经修改，则更新配置文件
if [ "$FIXED_URL" != "$MASTER_URL" ]; then
    info "需要修复URL: $MASTER_URL -> $FIXED_URL"
    sed -i "s|\"masterUrl\"[[:space:]]*:[[:space:]]*\"$MASTER_URL\"|\"masterUrl\": \"$FIXED_URL\"|g" "$CONFIG_FILE"
    success "配置文件已更新"
    
    info "修复后的配置:"
    grep -A 1 "masterUrl" "$CONFIG_FILE"
else
    info "URL格式已经正确，无需修改"
fi

# 询问是否需要重新编译和重启代理
read -p "是否需要重新编译并重启代理? (y/n): " rebuild
if [ "$rebuild" = "y" ] || [ "$rebuild" = "Y" ]; then
    # 尝试查找代理源码目录
    if [ -f "./client/agent.go" ]; then
        SRC_DIR="./"
    elif [ -f "../client/agent.go" ]; then
        SRC_DIR="../"
    else
        warn "找不到代理源码，请指定项目根目录:"
        read -p "项目根目录: " SRC_DIR
        
        if [ ! -f "${SRC_DIR}/client/agent.go" ]; then
            error "找不到代理源码: ${SRC_DIR}/client/agent.go"
            exit 1
        fi
    fi
    
    info "开始重新编译代理..."
    
    # 确保go.mod存在
    if [ ! -f "${SRC_DIR}/go.mod" ]; then
        warn "找不到go.mod文件，尝试初始化..."
        (cd "$SRC_DIR" && go mod init gosynflood)
    fi
    
    # 编译代理
    (cd "$SRC_DIR" && go build -o bin/attack-agent client/agent.go)
    
    if [ $? -eq 0 ]; then
        success "代理编译成功"
        
        # 尝试重启代理
        if [ -f "${SRC_DIR}/bin/start-agent.sh" ]; then
            info "尝试重启代理..."
            (cd "${SRC_DIR}/bin" && ./start-agent.sh)
            success "代理重启完成"
        else
            warn "找不到启动脚本 ${SRC_DIR}/bin/start-agent.sh"
            warn "请手动重启代理"
        fi
    else
        error "代理编译失败"
    fi
fi

info "修复脚本执行完成" 