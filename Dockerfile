FROM golang:1.18-alpine AS backend-builder

WORKDIR /app

# 安装必要的构建工具
RUN apk add --no-cache git

# 复制后端Go模块文件并下载依赖
COPY go.mod ./
COPY backend/go.mod ./backend/
RUN cd backend && go mod download

# 复制后端源代码
COPY backend/ ./backend/
COPY *.go ./

# 构建后端
RUN cd backend && CGO_ENABLED=0 GOOS=linux go build -o /app/bin/attack-server main.go

# 前端构建阶段
FROM node:16-alpine AS frontend-builder

WORKDIR /app

# 复制前端依赖文件并安装依赖
COPY frontend/package*.json ./
RUN npm install --no-fund --no-audit

# 复制前端源代码
COPY frontend/ ./

# 构建前端
RUN npm run build

# 最终阶段
FROM alpine:3.16

WORKDIR /app

# 安装运行时依赖
RUN apk add --no-cache ca-certificates tzdata

# 创建必要的目录
RUN mkdir -p /app/bin /app/data /app/backend/static

# 从构建阶段复制构建产物
COPY --from=backend-builder /app/bin/attack-server /app/bin/
COPY --from=frontend-builder /app/dist/ /app/backend/static/
COPY backend/config.json /app/backend/

# 设置默认的管理员令牌（在启动时可以通过环境变量覆盖）
ENV ADMIN_TOKEN="change-me-to-secure-token"

# 创建并配置auth.go文件
RUN mkdir -p /app/backend/middleware
RUN echo 'package middleware\n\nimport (\n\t"net/http"\n)\n\nvar (\n    AdminToken = "'$ADMIN_TOKEN'" \n)\n\n// AdminAuthMiddleware 验证管理员令牌\nfunc AdminAuthMiddleware(next http.HandlerFunc) http.HandlerFunc {\n\treturn func(w http.ResponseWriter, r *http.Request) {\n\t\ttoken := r.Header.Get("X-Admin-Token")\n\t\tif token != AdminToken {\n\t\t\thttp.Error(w, "未授权访问", http.StatusUnauthorized)\n\t\t\treturn\n\t\t}\n\t\tnext(w, r)\n\t}\n}' > /app/backend/middleware/auth.go

# 暴露服务端口
EXPOSE 31457

# 创建启动脚本
RUN echo '#!/bin/sh\n\n# 更新管理员令牌\nif [ ! -z "$ADMIN_TOKEN" ]; then\n  sed -i "s/AdminToken = \".*\"/AdminToken = \"$ADMIN_TOKEN\"/g" /app/backend/middleware/auth.go\n  echo "管理员令牌已更新"\nfi\n\n# 启动服务器\ncd /app\nexec /app/bin/attack-server -config /app/backend/config.json\n' > /app/start.sh && chmod +x /app/start.sh

# 设置启动命令
CMD ["/app/start.sh"] 