import axios from 'axios'

// 创建axios实例
const api = axios.create({
  baseURL: process.env.VUE_APP_API_URL || '/api',
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json'
  }
})

// 请求拦截器，添加认证令牌
api.interceptors.request.use(config => {
  // 从localStorage获取保存的令牌
  const adminToken = localStorage.getItem('adminToken')
  
  // 如果有令牌，添加到请求头
  if (adminToken) {
    config.headers['X-Admin-Token'] = adminToken
  }
  
  return config
}, error => {
  return Promise.reject(error)
})

// 响应拦截器处理错误
api.interceptors.response.use(
  response => response.data,
  error => {
    // 特殊处理认证错误
    if (error.response && error.response.status === 401) {
      // 清除无效的令牌
      localStorage.removeItem('adminToken')
      
      // 如果不在登录页面，重定向到登录页
      if (window.location.pathname !== '/static/login.html' && 
          window.location.pathname !== '/login-root.html') {
        window.location.href = '/login-root.html'
        return Promise.reject(new Error('认证已过期，请重新登录'))
      }
    }
    
    console.error('API请求错误:', error)
    return Promise.reject(error)
  }
)

// 服务器相关API
export const serverApi = {
  // 获取所有服务器
  getServers() {
    return api.get('/servers')
  },
  
  // 添加新服务器
  addServer(server) {
    return api.post('/servers', server)
  },
  
  // 删除服务器
  deleteServer(id) {
    return api.delete(`/servers/${id}`)
  }
}

// 攻击任务相关API
export const attackApi = {
  // 获取所有攻击任务
  getAttacks() {
    return api.get('/attacks')
  },
  
  // 创建新攻击任务
  createAttack(attack) {
    return api.post('/attacks', attack)
  },
  
  // 停止攻击任务
  stopAttack(id) {
    return api.post(`/attacks/${id}/stop`)
  }
}

// 用户认证相关API
export const authApi = {
  // 登录
  login(adminToken) {
    return api.post('/login', { adminToken })
  },
  
  // 检查当前认证状态
  checkAuth() {
    return api.get('/servers')
      .then(() => true)
      .catch(() => false)
  },
  
  // 登出
  logout() {
    localStorage.removeItem('adminToken')
    return Promise.resolve(true)
  }
}

// WebSocket服务
export const wsService = {
  connect(onMessage, onError) {
    const wsUrl = ((window.location.protocol === 'https:') ? 'wss://' : 'ws://') + 
                  window.location.host + 
                  '/ws'
    
    const socket = new WebSocket(wsUrl)
    
    socket.onopen = () => {
      console.log('WebSocket连接已建立')
    }
    
    socket.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data)
        if (onMessage) onMessage(data)
      } catch (e) {
        console.error('解析WebSocket消息失败:', e)
      }
    }
    
    socket.onerror = (error) => {
      console.error('WebSocket错误:', error)
      if (onError) onError(error)
    }
    
    socket.onclose = () => {
      console.log('WebSocket连接已关闭')
      // 自动重连逻辑
      setTimeout(() => {
        console.log('尝试重新连接WebSocket...')
        this.connect(onMessage, onError)
      }, 5000)
    }
    
    return socket
  }
}

export default {
  server: serverApi,
  attack: attackApi,
  auth: authApi,
  ws: wsService
} 