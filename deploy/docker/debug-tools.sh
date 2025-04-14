#!/bin/sh

# 前端构建调试工具
# 用法: ./debug-tools.sh [inspect|fix|test]

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 函数定义
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

inspect_frontend() {
  log_info "=== 前端构建环境检查 ==="

  # 检查Vue.js配置
  if [ -f "frontend/vue.config.js" ]; then
    log_info "Vue配置文件存在:"
    cat frontend/vue.config.js | grep -A 5 outputDir
  else
    log_error "找不到Vue配置文件!"
  fi

  # 检查package.json
  if [ -f "frontend/package.json" ]; then
    log_info "Package.json存在，检查构建脚本:"
    cat frontend/package.json | grep -A 10 scripts
  else
    log_error "找不到package.json文件!"
  fi

  # 检查静态文件目录
  if [ -d "backend/static" ]; then
    file_count=$(find backend/static -type f | wc -l)
    log_info "静态文件目录存在，包含 $file_count 个文件"
    if [ $file_count -gt 0 ]; then
      log_info "前10个文件:"
      find backend/static -type f | head -10
    else
      log_warn "静态文件目录为空!"
    fi
  else
    log_error "静态文件目录不存在!"
  fi

  # 检查其他可能的构建目录
  if [ -d "frontend/dist" ]; then
    dist_count=$(find frontend/dist -type f | wc -l)
    log_info "检测到frontend/dist目录，包含 $dist_count 个文件"
    if [ $dist_count -gt 0 ]; then
      log_info "该目录可能是构建输出目录，但没有被正确复制到backend/static"
    fi
  fi

  # 检查Docker配置
  if [ -f "Dockerfile" ]; then
    log_info "Dockerfile中的前端构建部分:"
    cat Dockerfile | grep -A 20 "前端构建阶段" | grep -B 20 "最终阶段"
  else
    log_error "找不到Dockerfile!"
  fi
}

fix_frontend() {
  log_info "=== 尝试修复前端构建问题 ==="

  # 确保目录存在
  mkdir -p backend/static

  # 检查是否有frontend/dist目录并复制内容
  if [ -d "frontend/dist" ] && [ $(find frontend/dist -type f | wc -l) -gt 0 ]; then
    log_info "从frontend/dist复制文件到backend/static"
    cp -rv frontend/dist/* backend/static/
    return 0
  fi

  # 如果没有构建产物，尝试构建前端
  if [ -f "frontend/package.json" ]; then
    log_info "尝试构建前端..."
    cd frontend
    npm install --no-fund --no-audit --production=false
    npm run build
    cd ..

    # 检查构建是否成功
    if [ -d "frontend/dist" ] && [ $(find frontend/dist -type f | wc -l) -gt 0 ]; then
      log_info "构建成功，复制文件到backend/static"
      cp -rv frontend/dist/* backend/static/
      return 0
    else
      log_error "构建失败或没有产生文件"
    fi
  fi

  # 如果上述方法都失败，创建简易前端页面
  log_warn "无法修复前端构建，创建简易页面"
  cat > backend/static/index.html << EOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>GOSYNFLOOD管理平台 - 简易版</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; padding: 0; background: #f4f4f4; color: #333; }
    .container { max-width: 800px; margin: 50px auto; padding: 20px; background: white; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
    h1 { color: #31708f; }
    .card { border: 1px solid #ddd; border-radius: 4px; padding: 15px; margin-bottom: 20px; }
    .card h2 { margin-top: 0; color: #31708f; }
    .btn { display: inline-block; padding: 6px 12px; margin-bottom: 0; font-size: 14px; font-weight: 400; text-align: center; white-space: nowrap; cursor: pointer; border: 1px solid transparent; border-radius: 4px; color: #fff; background-color: #337ab7; text-decoration: none; }
    .btn:hover { background-color: #286090; }
  </style>
</head>
<body>
  <div class="container">
    <h1>GOSYNFLOOD管理平台 - 简易版</h1>
    <p>注意: 这是一个简易版页面，实际前端构建似乎失败了。</p>
    
    <div class="card">
      <h2>系统状态</h2>
      <p>服务器已成功启动，API应该可以正常工作。</p>
      <p>您可以通过API直接与系统交互。</p>
    </div>
    
    <div class="card">
      <h2>API文档</h2>
      <p>系统提供以下API端点:</p>
      <ul>
        <li><code>/api/status</code> - 获取系统状态</li>
        <li><code>/api/servers</code> - 获取服务器列表</li>
        <li><code>/api/attack</code> - 控制攻击</li>
      </ul>
    </div>
    
    <p>如需更多帮助，请联系管理员或参考项目文档。</p>
    <p><a href="/debug.html" class="btn">查看调试信息</a></p>
  </div>
</body>
</html>
EOF

  log_info "创建完成"
  return 1
}

test_frontend() {
  log_info "=== 测试前端访问 ==="
  
  # 检查是否安装了curl
  if ! command -v curl &> /dev/null; then
    log_error "curl未安装，无法测试"
    return 1
  fi
  
  # 测试本地访问
  log_info "测试本地访问..."
  curl -s -o /dev/null -w "%{http_code}" http://localhost:31457/ | grep "200" > /dev/null
  if [ $? -eq 0 ]; then
    log_info "首页可以访问"
  else
    log_error "无法访问首页"
  fi
  
  # 检查index.html是否存在
  if [ -f "backend/static/index.html" ]; then
    log_info "index.html文件存在"
  else
    log_error "index.html文件不存在"
  fi
}

# 主函数
case "$1" in
  inspect)
    inspect_frontend
    ;;
  fix)
    fix_frontend
    ;;
  test)
    test_frontend
    ;;
  *)
    log_info "用法: ./debug-tools.sh [inspect|fix|test]"
    log_info "  inspect - 检查前端构建状态"
    log_info "  fix     - 尝试修复前端构建问题"
    log_info "  test    - 测试前端访问"
    ;;
esac 