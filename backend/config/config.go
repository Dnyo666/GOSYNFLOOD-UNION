package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
)

// Config 应用配置
type Config struct {
	// 服务器设置
	Host           string `json:"host"`
	Port           int    `json:"port"`
	StaticDir      string `json:"staticDir"`
	LogLevel       string `json:"logLevel"`
	AllowedOrigins string `json:"allowedOrigins"`
	DataDir        string `json:"dataDir"`
}

// 全局配置实例
var AppConfig Config

// 默认配置
const (
	defaultHost          = "0.0.0.0"
	defaultPort           = 31457
	defaultStaticDir      = "./static"
	defaultLogLevel       = "info"
	defaultAllowedOrigins = "*"
	defaultDataDir        = "./data"
)

// LoadConfig 加载配置
func LoadConfig(configFile string) error {
	// 设置默认值
	AppConfig = Config{
		Host:           defaultHost,
		Port:           defaultPort,
		StaticDir:      defaultStaticDir,
		LogLevel:       defaultLogLevel,
		AllowedOrigins: defaultAllowedOrigins,
		DataDir:        defaultDataDir,
	}

	// 尝试从配置文件加载
	if configFile != "" {
		if err := loadFromFile(configFile); err != nil {
			return fmt.Errorf("加载配置文件失败: %v", err)
		}
	}

	// 从环境变量覆盖
	loadFromEnv()

	// 确保数据目录存在
	if err := ensureDataDir(); err != nil {
		return fmt.Errorf("创建数据目录失败: %v", err)
	}

	return nil
}

// 从文件加载配置
func loadFromFile(configFile string) error {
	data, err := os.ReadFile(configFile)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // 文件不存在时使用默认值
		}
		return err
	}

	return json.Unmarshal(data, &AppConfig)
}

// 从环境变量加载配置
func loadFromEnv() {
	// 服务器主机
	if host := os.Getenv("AP_HOST"); host != "" {
		AppConfig.Host = host
	}
	
	// 服务器端口
	if port := os.Getenv("AP_PORT"); port != "" {
		if p, err := strconv.Atoi(port); err == nil {
			AppConfig.Port = p
		}
	}

	// 静态文件目录
	if staticDir := os.Getenv("AP_STATIC_DIR"); staticDir != "" {
		AppConfig.StaticDir = staticDir
	}

	// 日志级别
	if logLevel := os.Getenv("AP_LOG_LEVEL"); logLevel != "" {
		AppConfig.LogLevel = logLevel
	}

	// 允许的来源
	if origins := os.Getenv("AP_ALLOWED_ORIGINS"); origins != "" {
		AppConfig.AllowedOrigins = origins
	}

	// 数据目录
	if dataDir := os.Getenv("AP_DATA_DIR"); dataDir != "" {
		AppConfig.DataDir = dataDir
	}
}

// 确保数据目录存在
func ensureDataDir() error {
	if AppConfig.DataDir == "" {
		AppConfig.DataDir = defaultDataDir
	}

	// 创建数据目录（如果不存在）
	if err := os.MkdirAll(AppConfig.DataDir, 0755); err != nil {
		return err
	}

	// 检查是否需要创建子目录
	serversDir := filepath.Join(AppConfig.DataDir, "servers")
	attacksDir := filepath.Join(AppConfig.DataDir, "attacks")

	if err := os.MkdirAll(serversDir, 0755); err != nil {
		return err
	}

	if err := os.MkdirAll(attacksDir, 0755); err != nil {
		return err
	}

	return nil
} 