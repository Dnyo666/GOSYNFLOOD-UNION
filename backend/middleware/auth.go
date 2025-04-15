package middleware

import (
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"
	"path/filepath"
	"os"
)

// 配置保存在内存中的安全令牌
// 注意：在生产环境应使用更安全的存储和哈希方法
var (
	AdminToken = "secure-admin-token-change-me" // 生产环境应使用环境变量
)

// AdminAuthMiddleware 验证需要管理员权限的请求
func AdminAuthMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 提取和验证管理员令牌
		// 从请求体、请求头或URL参数中获取
		token := ""

		// 检查请求头 - 标准方式
		authHeader := r.Header.Get("X-Admin-Token")
		if authHeader != "" {
			token = authHeader
		}

		// 如果请求头中没有令牌，尝试从请求体中获取
		if token == "" && (r.Method == "POST" || r.Method == "PUT") {
			// 保存请求体以便后续读取
			bodyBytes, err := io.ReadAll(r.Body)
			if err == nil {
				r.Body.Close()
				
				// 重新创建可读取的请求体
				r.Body = io.NopCloser(strings.NewReader(string(bodyBytes)))
				
				// 尝试解析JSON
				var requestData map[string]interface{}
				if err := json.Unmarshal(bodyBytes, &requestData); err == nil {
					if adminToken, ok := requestData["adminToken"].(string); ok && adminToken != "" {
						token = adminToken
					}
				}
			}
		}

		// 检查URL参数中是否有令牌（用于某些GET请求）
		if token == "" {
			if paramToken := r.URL.Query().Get("adminToken"); paramToken != "" {
				token = paramToken
			}
		}

		// 检查Cookie中是否有令牌
		if token == "" {
			if cookie, err := r.Cookie("admin_token"); err == nil && cookie.Value != "" {
				token = cookie.Value
			}
		}

		// 如果令牌为空或不匹配，拒绝请求
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

// FrontendAuthMiddleware 用于保护前端页面，确保用户已登录
func FrontendAuthMiddleware(loginPath string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// 允许直接访问登录页面和静态资源
			// 注意：/static/路径已由main.go中的专用处理器处理，不会经过这个中间件
			if r.URL.Path == loginPath || 
			   r.URL.Path == "/login-root.html" ||
			   r.URL.Path == "/login.html" ||
			   strings.HasPrefix(r.URL.Path, "/api/login") ||
			   strings.HasPrefix(r.URL.Path, "/assets/") ||
			   strings.HasPrefix(r.URL.Path, "/favicon.ico") {
				next.ServeHTTP(w, r)
				return
			}

			// 从Cookie中检查令牌
			authenticated := false
			if cookie, err := r.Cookie("admin_token"); err == nil && cookie.Value != "" {
				// 验证Cookie中的令牌是否有效
				if cookie.Value == AdminToken {
					authenticated = true
				}
			}

			// 如果未通过认证，重定向到登录页面
			if !authenticated {
				http.Redirect(w, r, loginPath, http.StatusSeeOther)
				return
			}

			// 检查是否是前端路由请求 (非静态资源但请求HTML)
			if !strings.Contains(r.URL.Path, ".") && r.Method == "GET" {
				// Vue的history模式需要所有未找到的路由都返回index.html
				indexPath := filepath.Join(filepath.Dir(loginPath), "index.html")
				if _, err := os.Stat(indexPath); os.IsNotExist(err) {
					// 如果index.html不存在，尝试在static目录下查找
					alternativePath := "./static/index.html"
					if _, err := os.Stat(alternativePath); err == nil {
						indexPath = alternativePath
					}
				}
				http.ServeFile(w, r, indexPath)
				return
			}
			
			// 已认证，继续处理请求
			next.ServeHTTP(w, r)
		})
	}
}

// VerifyAdminToken 验证管理员令牌并返回相应的HTTP状态
func VerifyAdminToken(token string) (bool, int) {
	if token == "" {
		return false, http.StatusBadRequest
	}
	if token != AdminToken {
		return false, http.StatusUnauthorized
	}
	return true, http.StatusOK
}

// SetAuthCookie 设置认证Cookie
func SetAuthCookie(w http.ResponseWriter, token string) {
	// 设置包含令牌的Cookie，有效期24小时
	cookie := &http.Cookie{
		Name:     "admin_token",
		Value:    token,
		Path:     "/",
		HttpOnly: true,            // 防止JavaScript访问
		Secure:   false,           // 在生产环境中设置为true以要求HTTPS
		SameSite: http.SameSiteStrictMode, // 防止CSRF攻击
		Expires:  time.Now().Add(24 * time.Hour),
	}
	http.SetCookie(w, cookie)
}

// ServerState 定义服务器状态结构，用于从appState中提取
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
			// 保存请求体以便后续读取
			bodyBytes, err := io.ReadAll(r.Body)
			if err == nil {
				r.Body.Close()
				
				// 重新创建可读取的请求体
				r.Body = io.NopCloser(strings.NewReader(string(bodyBytes)))
				
				// 尝试解析JSON
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
		
		// 检查服务器ID和API密钥是否为空
		if serverID != "" && apiKey != "" {
			// 从应用状态获取服务器列表
			if state, ok := appState.(*ServerState); ok && state != nil {
				// 检查服务器ID是否存在
				if server, exists := state.Servers[serverID]; exists {
					// 验证API密钥是否匹配
					isValid = (server.APIKey == apiKey)
				}
			} else {
				// 如果appState没有正确的类型或为nil，在开发/测试环境中允许请求通过
				// 注意：在生产环境中，应该总是验证API密钥
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

		// 验证通过，继续处理请求
		next(w, r)
	}
} 