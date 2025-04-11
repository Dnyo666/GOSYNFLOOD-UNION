package main

import (
	"strings"
	"unsafe"
)

/*

#define _GNU_SOURCE
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netdb.h>
#include <ifaddrs.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <linux/if_link.h>
#include <string.h>
#include <limits.h>


char* getifaces()
{
    struct ifaddrs *ifaddr, *ifa;
    int family, s;
    char host[NI_MAXHOST];
    // 初始分配一个较大的缓冲区，避免频繁重新分配
    size_t buffer_size = 1024;
    char* interfaces = (char*) malloc(buffer_size);
    
    if (interfaces == NULL) {
        perror("malloc failed");
        exit(EXIT_FAILURE);
    }
    
    // 初始化为空字符串
    interfaces[0] = '\0';
    
    if (getifaddrs(&ifaddr) == -1) {
        free(interfaces);
        perror("getifaddrs");
        exit(EXIT_FAILURE);
    }
    
    for (ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr == NULL)
            continue;
            
        family = ifa->ifa_addr->sa_family;
        
        if (family == AF_INET || family == AF_INET6) {
            s = getnameinfo(ifa->ifa_addr,
                    (family == AF_INET) ? sizeof(struct sockaddr_in) :
                                            sizeof(struct sockaddr_in6),
                    host, NI_MAXHOST,
                    NULL, 0, NI_NUMERICHOST);
                    
            // 计算需要添加的接口名称加逗号的长度
            size_t iface_name_len = strlen(ifa->ifa_name);
            size_t current_len = strlen(interfaces);
            size_t needed_size = current_len + iface_name_len + 2; // +2 for comma and null terminator
            
            // 检查是否需要扩展缓冲区
            if (needed_size > buffer_size) {
                buffer_size = needed_size * 2; // 翻倍以减少重新分配次数
                char* new_buf = (char*) realloc(interfaces, buffer_size);
                if (new_buf == NULL) {
                    free(interfaces);
                    freeifaddrs(ifaddr);
                    perror("realloc failed");
                    exit(EXIT_FAILURE);
                }
                interfaces = new_buf;
            }
            
            // 拼接接口名称和逗号
            strcat(interfaces, ifa->ifa_name);
            strcat(interfaces, ",");
        }
    }
    
    freeifaddrs(ifaddr);
    return interfaces;
}

*/
import "C"

// getInterfaces binds to the C getifaces() function.
func (tcp *TCPIP) getInterfaces() []string {
	ifacesPTR := C.getifaces()
	var ifaces string = C.GoString(ifacesPTR)
	defer C.free(unsafe.Pointer(ifacesPTR))
	var interfaces []string
	for _, adapter := range strings.Split(ifaces, ",") {
		if len(adapter) < 1 {
			continue
		}
		isDup := false
		for _, ifaceName := range interfaces {
			if ifaceName != adapter {
				continue
			}
			isDup = true
			break
		}
		if !isDup {
			interfaces = append(interfaces, adapter)
		}
	}
	return interfaces
}
