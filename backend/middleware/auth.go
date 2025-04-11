package middleware

import (
	"encoding/json"
	"io"
	"net/http"
	"strings"
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

		// 检查请求头
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
					if adminToken, ok := requestData["adminToken"].(string); ok {
						token = adminToken
					}
				}
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
					if sid, ok := requestData["serverId"].(float64); ok {
						serverID = string(int(sid))
					}
					if ak, ok := requestData["apiKey"].(string); ok {
						apiKey = ak
					}
				}
			}
		}

		// 这里应该查询应用状态检查服务器ID和API密钥是否匹配
		// 实际实现时，应该从appState中验证
		isValid := false
		
		// TODO: 实现实际的API密钥验证
		// 简单演示，总是失败
		isValid = false
		
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