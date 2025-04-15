FROM golang:1.18-alpine AS backend-builder

WORKDIR /app

# 安装必要的构建工具
RUN apk add --no-cache git

# 复制Go模块文件
COPY go.mod ./
COPY backend/go.mod ./backend/

# 创建空的go.sum文件（如果不存在）
RUN touch go.sum
RUN touch backend/go.sum

# 先处理后端依赖，先添加gorilla/mux依赖，再进行依赖管理
RUN cd backend && \
    # 检查并添加gorilla/mux依赖
    grep -q "github.com/gorilla/mux" go.mod || echo "require github.com/gorilla/mux v1.8.0" >> go.mod && \
    # 整理依赖并下载
    go mod tidy && \
    go mod download

# 复制后端源代码
COPY backend/ ./backend/
COPY *.go ./

# 构建后端
RUN cd backend && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /app/bin/attack-server main.go

# 前端构建阶段
FROM node:16-alpine AS frontend-builder

WORKDIR /app

# 安装构建工具和调试工具
RUN apk add --no-cache curl jq tree

# 复制前端依赖文件并安装
COPY frontend/package*.json ./frontend/
RUN echo "=== 安装前端依赖 ===" && \
    cd frontend && \
    npm install --no-fund --no-audit --production=false && \
    echo "依赖安装完成, node_modules 目录大小: $(du -sh node_modules | cut -f1)"

# 复制前端源代码
COPY frontend/ ./frontend/

# 显示Vue配置以验证输出目录
RUN echo "=== Vue.js配置分析 ===" && \
    if [ -f "frontend/vue.config.js" ]; then \
      cat frontend/vue.config.js | grep outputDir; \
      echo "Vue配置文件存在，准备构建前端"; \
    else \
      echo "警告: 找不到vue.config.js文件"; \
    fi

# 确保目标目录存在并显示目录结构
RUN mkdir -p backend/static && \
    echo "=== 构建前目录结构 ===" && \
    ls -la && \
    echo "frontend目录:" && \
    ls -la frontend

# 构建前端（在frontend目录下运行）并记录结果
RUN cd frontend && \
    echo "=== 开始构建前端 ===" && \
    npm run build | tee /tmp/build.log || { \
      echo "=== 构建失败! 显示错误日志 ==="; \
      tail -n 50 /tmp/build.log; \
      exit 1; \
    }

# 验证构建产物
RUN echo "=== 构建后目录结构 ===" && \
    ls -la && \
    echo "backend/static目录:" && \
    ls -la backend/static 2>/dev/null || echo "backend/static目录不存在" && \
    echo "前端构建产物文件数量: $(find backend/static -type f 2>/dev/null | wc -l)" && \
    echo "前端构建产物文件列表(前10个):" && \
    find backend/static -type f 2>/dev/null | sort | head -10

# 为处理可能存在的Vue路径问题添加备份措施
RUN if [ "$(find backend/static -type f 2>/dev/null | wc -l)" = "0" ] && [ -d "frontend/dist" ]; then \
      echo "=== 检测到Vue可能将文件输出到frontend/dist目录，正在复制... ==="; \
      cp -rv frontend/dist/* backend/static/ 2>/dev/null || echo "复制失败或目录为空"; \
    fi

# 最终阶段
FROM alpine:3.16

WORKDIR /app

# 安装运行时依赖
RUN apk add --no-cache ca-certificates tzdata

# 创建必要的目录
RUN mkdir -p /app/bin /app/data /app/backend/static

# 从构建阶段复制构建产物
COPY --from=backend-builder /app/bin/attack-server /app/bin/

# 复制前端构建产物
COPY --from=frontend-builder /app/backend/static/ /app/backend/static/

# 确保静态目录有内容，如果没有创建一个临时页面
RUN if [ -z "$(ls -A /app/backend/static 2>/dev/null)" ]; then \
    echo "警告: 静态文件目录为空，创建临时页面" && \
    echo '<html><body><h1>GOSYNFLOOD管理平台</h1><p>警告: 前端构建失败。</p></body></html>' > /app/backend/static/index.html; \
    else \
    echo "静态文件已复制，文件数: $(find /app/backend/static -type f | wc -l)"; \
    fi

# 确保login-root.html总是存在
RUN echo '<!DOCTYPE html><html><head><meta charset="UTF-8"><meta http-equiv="refresh" content="0; url=/static/login.html"><title>重定向到登录页</title></head><body><p>正在重定向到登录页...</p><script>window.location.href = "/static/login.html";</script></body></html>' > /app/backend/static/login-root.html

# 复制配置文件
COPY backend/config.json /app/backend/

# 设置默认的管理员令牌（在启动时可以通过环境变量覆盖）
ENV ADMIN_TOKEN="change-me-to-secure-token"

# 创建并配置auth.go文件
RUN mkdir -p /app/backend/middleware
RUN echo 'package middleware\n\nimport (\n\t"net/http"\n)\n\nvar (\n    AdminToken = "'$ADMIN_TOKEN'" \n)\n\n// AdminAuthMiddleware 验证管理员令牌\nfunc AdminAuthMiddleware(next http.HandlerFunc) http.HandlerFunc {\n\treturn func(w http.ResponseWriter, r *http.Request) {\n\t\ttoken := r.Header.Get("X-Admin-Token")\n\t\tif token != AdminToken {\n\t\t\thttp.Error(w, "未授权访问", http.StatusUnauthorized)\n\t\t\treturn\n\t\t}\n\t\tnext(w, r)\n\t}\n}' > /app/backend/middleware/auth.go

# 暴露服务端口
EXPOSE 31457

# 复制启动脚本并设置执行权限
COPY deploy/docker/start.sh /app/start.sh
RUN chmod +x /app/start.sh

# 设置启动命令
CMD ["/app/start.sh"] 