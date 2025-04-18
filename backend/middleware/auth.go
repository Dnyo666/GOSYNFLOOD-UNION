package middleware

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"strings"
	"time"
	"os"
)

// 配置保存在内存中的安全令牌
var (
	AdminToken = "secure-admin-token-change-me" // 生产环境会由环境变量覆盖
)

// 初始化函数，从环境变量加载令牌
func init() {
	// 从环境变量获取管理员令牌
	if envToken := os.Getenv("ADMIN_TOKEN"); envToken != "" {
		log.Printf("从环境变量加载管理员令牌，长度: %d", len(envToken))
		AdminToken = envToken
	} else {
		log.Printf("警告: 未设置ADMIN_TOKEN环境变量，使用默认令牌")
	}
}

// AdminAuthMiddleware 验证需要管理员权限的请求
func AdminAuthMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 提取和验证管理员令牌
		token := ""

		// 1. 检查请求头
		authHeader := r.Header.Get("X-Admin-Token")
		if authHeader != "" {
			token = authHeader
		}

		// 2. 检查请求体 (对于POST/PUT请求)
		if token == "" && (r.Method == "POST" || r.Method == "PUT") {
			bodyBytes, err := io.ReadAll(r.Body)
			if err == nil {
				r.Body.Close()
				r.Body = io.NopCloser(strings.NewReader(string(bodyBytes)))
				
				var requestData map[string]interface{}
				if err := json.Unmarshal(bodyBytes, &requestData); err == nil {
					if adminToken, ok := requestData["adminToken"].(string); ok && adminToken != "" {
						token = adminToken
					}
				}
			}
		}

		// 3. 检查URL参数
		if token == "" {
			if paramToken := r.URL.Query().Get("adminToken"); paramToken != "" {
				token = paramToken
			}
		}

		// 4. 检查Cookie
		if token == "" {
			if cookie, err := r.Cookie("admin_token"); err == nil && cookie.Value != "" {
				token = cookie.Value
			}
		}

		// 验证令牌
		if token == "" || token != AdminToken {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusUnauthorized)
			json.NewEncoder(w).Encode(map[string]string{
				"error": "需要有效的管理员令牌",
			})
			return
		}

		// 令牌有效，继续处理请求
		next(w, r)
	}
}

// FrontendAuthMiddleware 保护前端页面，确保用户已登录
func FrontendAuthMiddleware(loginPath string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// 允许直接访问静态资源，无需认证
			if strings.HasPrefix(r.URL.Path, "/static/") {
				next.ServeHTTP(w, r)
				return
			}
			
			// 登录相关页面无需认证
			if r.URL.Path == "/login" || r.URL.Path == "/login.html" || r.URL.Path == "/login-root.html" {
				// 对于login-root.html，直接提供login.html文件
				if r.URL.Path == "/login-root.html" {
					http.ServeFile(w, r, "/app/backend/static/login.html")
					return
				}
				
				// 其他登录相关页面放行
				next.ServeHTTP(w, r)
				return
			}

			// 从Cookie中验证令牌
			cookie, err := r.Cookie("admin_token")
			if err != nil || cookie.Value != AdminToken {
				// 未登录，重定向到登录页面
				http.Redirect(w, r, "/login-root.html", http.StatusSeeOther)
				return
			}

			// 处理前端路由 (不包含扩展名的请求视为前端路由)
			if r.URL.Path == "/" || !strings.Contains(r.URL.Path, ".") {
				indexPath := "/app/backend/static/index.html"
				
				// 检查index.html是否存在
				if _, err := os.Stat(indexPath); os.IsNotExist(err) {
					// 尝试查找备用路径
					alternativePaths := []string{
						"./static/index.html",
						"/app/frontend/dist/index.html",
					}
					
					for _, path := range alternativePaths {
						if _, err := os.Stat(path); err == nil {
							indexPath = path
							break
						}
					}
					
					// 如果所有路径都不存在
					if _, err := os.Stat(indexPath); os.IsNotExist(err) {
						http.Error(w, "前端文件未找到，请检查构建过程", http.StatusNotFound)
						return
					}
				}
				
				// 提供index.html文件
				http.ServeFile(w, r, indexPath)
				return
			}
			
			// 已认证的其他请求放行
			next.ServeHTTP(w, r)
		})
	}
}

// SetAuthCookie 设置认证Cookie
func SetAuthCookie(w http.ResponseWriter, token string) {
	cookie := &http.Cookie{
		Name:     "admin_token",
		Value:    token,
		Path:     "/",
		HttpOnly: true,
		Secure:   false,
		SameSite: http.SameSiteStrictMode,
		Expires:  time.Now().Add(24 * time.Hour),
	}
	http.SetCookie(w, cookie)
}

// VerifyAdminToken 验证管理员令牌
func VerifyAdminToken(token string) (bool, int) {
	if token == "" {
		log.Printf("验证失败: 令牌为空")
		return false, http.StatusBadRequest // 400 错误
	}
	if token != AdminToken {
		log.Printf("验证失败: 令牌不匹配 (输入长度: %d, 有效长度: %d)", len(token), len(AdminToken))
		return false, http.StatusUnauthorized // 401 错误
	}
	log.Printf("令牌验证成功")
	return true, http.StatusOK // 200 成功
}

// ServerState 定义服务器状态结构
type ServerState struct {
	Servers map[string]Server
}

// Server 定义单个服务器的结构
type Server struct {
	ID     string
	Name   string
	IP     string
	Port   int
	APIKey string
}

// APIKeyMiddleware 验证攻击代理的API密钥
func APIKeyMiddleware(appState interface{}, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 从查询参数或请求体中获取服务器ID和API密钥
		serverID := r.URL.Query().Get("serverId")
		apiKey := r.URL.Query().Get("apiKey")

		// 如果查询参数中没有，尝试从请求体中获取
		if (serverID == "" || apiKey == "") && (r.Method == "POST" || r.Method == "PUT") {
			bodyBytes, err := io.ReadAll(r.Body)
			if err == nil {
				r.Body.Close()
				r.Body = io.NopCloser(strings.NewReader(string(bodyBytes)))
				
				var requestData map[string]interface{}
				if err := json.Unmarshal(bodyBytes, &requestData); err == nil {
					if sid, ok := requestData["serverId"].(string); ok {
						serverID = sid
					} else if sid, ok := requestData["serverId"].(float64); ok {
						serverID = string(int(sid))
					}
					
					if ak, ok := requestData["apiKey"].(string); ok {
						apiKey = ak
					}
				}
			}
		}

		// 实现API密钥验证逻辑
		isValid := false
		
		if serverID != "" && apiKey != "" {
			if state, ok := appState.(*ServerState); ok && state != nil {
				if server, exists := state.Servers[serverID]; exists {
					isValid = (server.APIKey == apiKey)
				}
			} else {
				isValid = true
			}
		}
		
		if !isValid {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusUnauthorized)
			json.NewEncoder(w).Encode(map[string]string{
				"error": "无效的服务器ID或API密钥",
			})
			return
		}

		next(w, r)
	}
} 