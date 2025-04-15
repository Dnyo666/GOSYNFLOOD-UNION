package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/mux"
	"github.com/gorilla/websocket"
	"github.com/rs/cors"
	
	"github.com/Dnyo666/gosynflood-union/backend/config"
	"github.com/Dnyo666/gosynflood-union/backend/middleware"
)

// 服务器状态类型
type ServerStatus string

const (
	ServerStatusOnline  ServerStatus = "online"
	ServerStatusOffline ServerStatus = "offline"
	ServerStatusBusy    ServerStatus = "busy"
)

// Server 表示一个攻击服务器
type Server struct {
	ID        int         `json:"id"`
	Name      string      `json:"name"`
	IP        string      `json:"ip"`
	Port      int         `json:"port"`
	APIKey    string      `json:"-"` // 不返回给客户端
	Status    ServerStatus `json:"status"`
	LastSeen  time.Time   `json:"lastSeen"`
	PacketsSent uint64    `json:"packetsSent"`
	PacketsRate uint64    `json:"packetsRate"`
}

// Attack 表示一个攻击任务
type Attack struct {
	ID              int       `json:"id"`
	Name            string    `json:"name"`
	TargetIP        string    `json:"targetIp"`
	TargetPort      int       `json:"targetPort"`
	Duration        int       `json:"duration"` // 0表示不限时间
	PacketsPerSecond int      `json:"packetsPerSecond"` // 0表示不限速
	StartTime       time.Time `json:"startTime"`
	EndTime         time.Time `json:"endTime,omitempty"`
	Status          string    `json:"status"` // planning, running, completed, failed
	Servers         []int     `json:"servers"` // 服务器ID列表
	TotalPacketsSent uint64   `json:"totalPacketsSent"`
	CurrentRate     uint64    `json:"currentRate"`
}

// 应用状态
type AppState struct {
	Servers     map[int]*Server
	Attacks     map[int]*Attack
	NextServerID int
	NextAttackID int
	mu          sync.RWMutex
}

// WebSocket处理
var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // 允许所有跨域请求
	},
}

// WebSocket客户端连接
type Client struct {
	conn *websocket.Conn
}

var clients = make(map[*Client]bool)
var clientMu sync.Mutex

// 全局应用状态
var appState = AppState{
	Servers:     make(map[int]*Server),
	Attacks:     make(map[int]*Attack),
	NextServerID: 1,
	NextAttackID: 1,
}

// 广播更新
func broadcastUpdate(update interface{}) {
	data, err := json.Marshal(update)
	if err != nil {
		log.Printf("广播失败: %v", err)
		return
	}

	clientMu.Lock()
	defer clientMu.Unlock()

	for client := range clients {
		err := client.conn.WriteMessage(websocket.TextMessage, data)
		if err != nil {
			log.Printf("客户端写入失败: %v", err)
			client.conn.Close()
			delete(clients, client)
		}
	}
}

// 处理WebSocket连接
func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("WebSocket升级失败:", err)
		return
	}

	client := &Client{conn: conn}
	
	clientMu.Lock()
	clients[client] = true
	clientMu.Unlock()

	// 立即发送初始状态
	appState.mu.RLock()
	initialState := map[string]interface{}{
		"type":    "initial_state",
		"servers": appState.Servers,
		"attacks": appState.Attacks,
	}
	appState.mu.RUnlock()
	
	data, _ := json.Marshal(initialState)
	client.conn.WriteMessage(websocket.TextMessage, data)

	// 监听客户端消息
	go func() {
		defer func() {
			clientMu.Lock()
			delete(clients, client)
			clientMu.Unlock()
			conn.Close()
		}()

		for {
			_, _, err := conn.ReadMessage()
			if err != nil {
				if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
					log.Printf("WebSocket错误: %v", err)
				}
				break
			}
		}
	}()
}

// API处理函数

// 获取所有服务器
func getServers(w http.ResponseWriter, r *http.Request) {
	appState.mu.RLock()
	servers := make([]*Server, 0, len(appState.Servers))
	for _, server := range appState.Servers {
		servers = append(servers, server)
	}
	appState.mu.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(servers)
}

// 添加新服务器
func addServer(w http.ResponseWriter, r *http.Request) {
	var server Server
	if err := json.NewDecoder(r.Body).Decode(&server); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	appState.mu.Lock()
	server.ID = appState.NextServerID
	appState.NextServerID++
	server.Status = ServerStatusOffline
	server.LastSeen = time.Now()
	appState.Servers[server.ID] = &server
	appState.mu.Unlock()

	// 广播更新
	update := map[string]interface{}{
		"type":   "server_added",
		"server": server,
	}
	broadcastUpdate(update)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(server)
}

// 删除服务器
func deleteServer(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]
	serverID := 0
	fmt.Sscanf(id, "%d", &serverID)

	appState.mu.Lock()
	defer appState.mu.Unlock()

	if _, exists := appState.Servers[serverID]; !exists {
		http.Error(w, "服务器不存在", http.StatusNotFound)
		return
	}

	delete(appState.Servers, serverID)

	// 广播更新
	update := map[string]interface{}{
		"type": "server_deleted",
		"id":   serverID,
	}
	broadcastUpdate(update)

	w.WriteHeader(http.StatusNoContent)
}

// 获取所有攻击任务
func getAttacks(w http.ResponseWriter, r *http.Request) {
	appState.mu.RLock()
	attacks := make([]*Attack, 0, len(appState.Attacks))
	for _, attack := range appState.Attacks {
		attacks = append(attacks, attack)
	}
	appState.mu.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(attacks)
}

// 创建新攻击任务
func createAttack(w http.ResponseWriter, r *http.Request) {
	var attack Attack
	if err := json.NewDecoder(r.Body).Decode(&attack); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// 验证攻击参数
	if attack.TargetIP == "" || attack.TargetPort <= 0 || attack.TargetPort > 65535 {
		http.Error(w, "无效的目标设置", http.StatusBadRequest)
		return
	}

	if len(attack.Servers) == 0 {
		http.Error(w, "未选择攻击服务器", http.StatusBadRequest)
		return
	}

	appState.mu.Lock()
	
	// 验证所有服务器都存在且在线
	for _, serverID := range attack.Servers {
		server, exists := appState.Servers[serverID]
		if !exists || server.Status != ServerStatusOnline {
			appState.mu.Unlock()
			http.Error(w, "选择的服务器不存在或离线", http.StatusBadRequest)
			return
		}
	}

	attack.ID = appState.NextAttackID
	appState.NextAttackID++
	attack.Status = "planning"
	attack.StartTime = time.Now()
	appState.Attacks[attack.ID] = &attack
	appState.mu.Unlock()

	// 广播更新
	update := map[string]interface{}{
		"type":   "attack_created",
		"attack": attack,
	}
	broadcastUpdate(update)

	// 在实际环境中，这里应该异步启动攻击
	go startAttack(&attack)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(attack)
}

// 停止攻击任务
func stopAttack(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]
	attackID := 0
	fmt.Sscanf(id, "%d", &attackID)

	appState.mu.Lock()
	attack, exists := appState.Attacks[attackID]
	if !exists {
		appState.mu.Unlock()
		http.Error(w, "攻击任务不存在", http.StatusNotFound)
		return
	}

	if attack.Status != "running" {
		appState.mu.Unlock()
		http.Error(w, "攻击任务不在运行中", http.StatusBadRequest)
		return
	}

	attack.Status = "completed"
	attack.EndTime = time.Now()
	appState.mu.Unlock()

	// 广播更新
	update := map[string]interface{}{
		"type":   "attack_stopped",
		"attack": attack,
	}
	broadcastUpdate(update)

	// 在实际环境中，这里应该发送停止命令到各个服务器

	w.WriteHeader(http.StatusNoContent)
}

// 模拟启动攻击
func startAttack(attack *Attack) {
	// 在实际环境中，这里应该向每个服务器发送开始攻击的命令
	time.Sleep(2 * time.Second) // 模拟准备过程

	appState.mu.Lock()
	attack.Status = "running"
	appState.mu.Unlock()

	// 广播状态更新
	update := map[string]interface{}{
		"type":   "attack_started",
		"attack": attack,
	}
	broadcastUpdate(update)

	// 模拟定期更新攻击状态
	go func() {
		ticker := time.NewTicker(1 * time.Second)
		defer ticker.Stop()

		var totalPackets uint64 = 0
		for range ticker.C {
			appState.mu.RLock()
			if attack.Status != "running" {
				appState.mu.RUnlock()
				break
			}
			appState.mu.RUnlock()

			// 模拟数据包增长
			packetIncrement := uint64(100000 + (time.Now().UnixNano() % 50000))
			totalPackets += packetIncrement

			appState.mu.Lock()
			attack.TotalPacketsSent = totalPackets
			attack.CurrentRate = packetIncrement
			appState.mu.Unlock()

			// 广播更新
			update := map[string]interface{}{
				"type":   "attack_stats_update",
				"id":     attack.ID,
				"packets": totalPackets,
				"rate":   packetIncrement,
			}
			broadcastUpdate(update)

			// 如果设置了持续时间，检查是否应该停止
			if attack.Duration > 0 {
				appState.mu.RLock()
				elapsed := time.Since(attack.StartTime).Seconds()
				appState.mu.RUnlock()

				if int(elapsed) >= attack.Duration {
					appState.mu.Lock()
					attack.Status = "completed"
					attack.EndTime = time.Now()
					appState.mu.Unlock()

					// 广播停止信息
					update := map[string]interface{}{
						"type":   "attack_stopped",
						"attack": attack,
					}
					broadcastUpdate(update)
					break
				}
			}
		}
	}()
}

// 代理服务器心跳处理
func serverHeartbeat(w http.ResponseWriter, r *http.Request) {
	var data struct {
		ServerID    int    `json:"serverId"`
		APIKey      string `json:"apiKey"`
		PacketsSent uint64 `json:"packetsSent"`
		PacketsRate uint64 `json:"packetsRate"`
	}

	if err := json.NewDecoder(r.Body).Decode(&data); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	appState.mu.Lock()
	server, exists := appState.Servers[data.ServerID]
	
	if !exists {
		appState.mu.Unlock()
		http.Error(w, "服务器不存在", http.StatusNotFound)
		return
	}

	if server.APIKey != data.APIKey {
		appState.mu.Unlock()
		http.Error(w, "API密钥无效", http.StatusUnauthorized)
		return
	}

	// 更新服务器状态
	server.Status = ServerStatusOnline
	server.LastSeen = time.Now()
	server.PacketsSent = data.PacketsSent
	server.PacketsRate = data.PacketsRate
	appState.mu.Unlock()

	// 广播更新
	update := map[string]interface{}{
		"type":   "server_updated",
		"server": server,
	}
	broadcastUpdate(update)

	w.WriteHeader(http.StatusOK)
}

// 处理客户端代理请求命令
func getCommands(w http.ResponseWriter, r *http.Request) {
	// 获取请求参数
	serverID := 0
	apiKey := ""

	// 从查询参数中获取服务器ID和API密钥
	if idStr := r.URL.Query().Get("serverId"); idStr != "" {
		fmt.Sscanf(idStr, "%d", &serverID)
	}
	if key := r.URL.Query().Get("apiKey"); key != "" {
		apiKey = key
	}

	// 验证服务器ID和API密钥
	appState.mu.RLock()
	server, exists := appState.Servers[serverID]
	appState.mu.RUnlock()

	if !exists {
		http.Error(w, "服务器不存在", http.StatusNotFound)
		return
	}

	if server.APIKey != apiKey {
		http.Error(w, "API密钥无效", http.StatusUnauthorized)
		return
	}

	// 查找是否有针对该服务器的命令
	var command struct {
		Type string      `json:"type"`
		Task interface{} `json:"task,omitempty"`
	}

	// 默认情况下没有命令
	command.Type = "none"

	// 查找正在运行的攻击任务，检查是否包含此服务器
	appState.mu.RLock()
	for _, attack := range appState.Attacks {
		// 检查攻击是否包含该服务器且状态为刚创建或运行中
		includesServer := false
		for _, sid := range attack.Servers {
			if sid == serverID {
				includesServer = true
				break
			}
		}

		if includesServer {
			if attack.Status == "planning" {
				// 新创建的攻击任务
				command.Type = "start_attack"
				command.Task = map[string]interface{}{
					"id":              attack.ID,
					"targetIp":        attack.TargetIP,
					"targetPort":      attack.TargetPort,
					"duration":        attack.Duration,
					"packetsPerSecond": attack.PacketsPerSecond,
				}
				
				// 更新攻击状态为运行中
				appState.mu.RUnlock()
				appState.mu.Lock()
				if attack, ok := appState.Attacks[attack.ID]; ok && attack.Status == "planning" {
					attack.Status = "running"
				}
				appState.mu.Unlock()
				appState.mu.RLock()
				
				break
			} else if attack.Status == "completed" || attack.Status == "failed" {
				// 已完成或失败的攻击，需要停止
				command.Type = "stop_attack"
				break
			}
		}
	}
	appState.mu.RUnlock()

	// 返回命令
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(command)
}

// 处理登录请求
func handleLogin(w http.ResponseWriter, r *http.Request) {
	// 只允许POST方法
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// 解析登录请求
	var loginRequest struct {
		AdminToken string `json:"adminToken"`
	}

	if err := json.NewDecoder(r.Body).Decode(&loginRequest); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "无效的请求格式",
		})
		return
	}

	// 验证管理员令牌
	valid, statusCode := middleware.VerifyAdminToken(loginRequest.AdminToken)
	if !valid {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(statusCode)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "登录失败：令牌无效",
		})
		return
	}

	// 设置认证Cookie
	middleware.SetAuthCookie(w, loginRequest.AdminToken)

	// 返回成功响应
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"message": "登录成功",
	})
}

func main() {
	// 添加命令行参数支持
	configPath := flag.String("config", "config.json", "配置文件路径")
	flag.Parse()
	
	// 加载配置
	if err := config.LoadConfig(*configPath); err != nil {
		log.Fatalf("加载配置失败: %v", err)
	}

	// 启动服务器状态监控
	go monitorServerStatus()

	// 设置路由
	r := mux.NewRouter()
	api := r.PathPrefix("/api").Subrouter()

	// 登录API路由
	api.HandleFunc("/login", handleLogin).Methods("POST", "OPTIONS")

	// 受保护的API路由 - 需要管理员权限
	api.HandleFunc("/servers", middleware.AdminAuthMiddleware(addServer)).Methods("POST")
	api.HandleFunc("/servers/{id}", middleware.AdminAuthMiddleware(deleteServer)).Methods("DELETE")
	api.HandleFunc("/attacks", middleware.AdminAuthMiddleware(createAttack)).Methods("POST")
	api.HandleFunc("/attacks/{id}/stop", middleware.AdminAuthMiddleware(stopAttack)).Methods("POST")

	// 公共API路由
	api.HandleFunc("/servers", getServers).Methods("GET")
	api.HandleFunc("/attacks", getAttacks).Methods("GET")
	
	// 代理API - 需要API密钥验证
	api.HandleFunc("/heartbeat", serverHeartbeat).Methods("POST")
	api.HandleFunc("/commands", getCommands).Methods("GET")

	// WebSocket连接
	r.HandleFunc("/ws", handleWebSocket)

	// 创建静态文件服务器
	fileServer := http.FileServer(http.Dir(config.AppConfig.StaticDir))
	
	// 显式处理/static/路径，直接使用静态文件服务器而不经过认证中间件
	r.PathPrefix("/static/").Handler(http.StripPrefix("/static/", fileServer))

	// 应用前端身份验证中间件
	// 使用根路径和静态路径的登录页面
	frontendHandler := middleware.FrontendAuthMiddleware("/login-root.html")(fileServer)
	r.PathPrefix("/").Handler(frontendHandler)

	// 设置CORS
	c := cors.New(cors.Options{
		AllowedOrigins:   []string{config.AppConfig.AllowedOrigins},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Content-Type", "X-Admin-Token"},
		AllowCredentials: true,
	})

	// 启动服务器
	handler := c.Handler(r)
	addr := fmt.Sprintf("%s:%d", config.AppConfig.Host, config.AppConfig.Port)
	log.Printf("服务器启动在 %s", addr)
	
	// 显示服务器可访问地址
	if config.AppConfig.Host == "0.0.0.0" || config.AppConfig.Host == "" {
		log.Printf("本地访问: http://localhost:%d", config.AppConfig.Port)
		log.Printf("要获取远程访问地址，请使用 'ip addr' 或 'hostname -I' 命令查看服务器IP地址")
	}
	
	log.Fatal(http.ListenAndServe(addr, handler))
}

// 监控服务器状态的后台任务
func monitorServerStatus() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		now := time.Now()
		appState.mu.Lock()
		
		for _, server := range appState.Servers {
			// 如果超过60秒未收到心跳，标记为离线
			if server.Status == ServerStatusOnline && now.Sub(server.LastSeen) > 60*time.Second {
				server.Status = ServerStatusOffline
				
				// 广播更新
				update := map[string]interface{}{
					"type":   "server_updated",
					"server": server,
				}
				go broadcastUpdate(update) // 在goroutine中广播以避免死锁
			}
		}
		
		appState.mu.Unlock()
	}
} 