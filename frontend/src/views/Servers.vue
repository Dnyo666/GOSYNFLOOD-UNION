<template>
  <div class="servers-page">
    <h1 class="page-title">攻击服务器管理</h1>
    
    <div class="page-description">
      <p>在这里管理您的攻击服务器。添加新服务器后，您需要在对应的服务器上启动攻击代理。</p>
    </div>
    
    <div class="card stats-card">
      <div class="stat-item">
        <div class="stat-icon online-icon">
          <i class="el-icon-success"></i>
        </div>
        <div class="stat-content">
          <div class="stat-title">在线服务器</div>
          <div class="stat-value">{{ onlineServers.length }}</div>
        </div>
      </div>
      
      <div class="stat-item">
        <div class="stat-icon offline-icon">
          <i class="el-icon-error"></i>
        </div>
        <div class="stat-content">
          <div class="stat-title">离线服务器</div>
          <div class="stat-value">{{ totalServers - onlineServers.length }}</div>
        </div>
      </div>
      
      <div class="stat-item">
        <div class="stat-icon capacity-icon">
          <i class="el-icon-data-line"></i>
        </div>
        <div class="stat-content">
          <div class="stat-title">总攻击能力</div>
          <div class="stat-value">{{ formatNumber(totalCapacity) }} 包/秒</div>
        </div>
      </div>
    </div>
    
    <div class="actions-bar">
      <button class="btn btn-primary" @click="showAddServerModal">
        <i class="el-icon-plus"></i> 添加攻击服务器
      </button>
    </div>
    
    <div v-if="servers.length === 0" class="empty-state card">
      <div class="empty-icon">
        <i class="el-icon-s-platform"></i>
      </div>
      <h3>没有找到攻击服务器</h3>
      <p>您需要添加至少一台攻击服务器才能开始执行分布式攻击。</p>
      <button class="btn btn-primary" @click="showAddServerModal">添加第一台服务器</button>
    </div>
    
    <div v-else class="servers-container">
      <div class="card" v-for="server in servers" :key="server.id">
        <div class="server-header">
          <div class="server-name">{{ server.name }}</div>
          <div class="status-badge" :class="server.status">
            {{ server.status === 'online' ? '在线' : '离线' }}
          </div>
        </div>
        
        <div class="server-body">
          <div class="server-info">
            <div class="info-row">
              <div class="info-label"><i class="el-icon-location"></i> IP地址</div>
              <div class="info-value">{{ server.ip }}</div>
            </div>
            <div class="info-row">
              <div class="info-label"><i class="el-icon-tickets"></i> ID</div>
              <div class="info-value">{{ server.id }}</div>
            </div>
            <div class="info-row">
              <div class="info-label"><i class="el-icon-time"></i> 上次活动</div>
              <div class="info-value">{{ formatLastSeen(server.lastSeen) }}</div>
            </div>
            <div class="info-row" v-if="server.status === 'online'">
              <div class="info-label"><i class="el-icon-data-analysis"></i> 发包速率</div>
              <div class="info-value">{{ formatNumber(server.packetsRate) }} 包/秒</div>
            </div>
          </div>
          
          <div class="server-setup" v-if="server.status !== 'online'">
            <h3>配置服务器代理</h3>
            <div class="setup-instructions">
              <p>在服务器 <strong>{{ server.ip }}</strong> 上运行以下命令启动攻击代理：</p>
              <div class="code-block">
                <code>
                  cd /path/to/attack-platform/bin<br>
                  sudo ./attack-agent -id {{ server.id }} -key {{ getServerKey(server) }} -master {{ apiBaseUrl }}
                </code>
                <button class="copy-btn" @click="copySetupCommand(server)">复制</button>
              </div>
              <p class="note">注意：攻击代理需要以root权限运行才能创建原始套接字。</p>
            </div>
          </div>
        </div>
        
        <div class="server-actions">
          <button class="btn" :class="server.status === 'online' ? 'btn-primary' : 'btn-disabled'"
                  @click="useServer(server)" :disabled="server.status !== 'online'">
            用于攻击
          </button>
          <button class="btn btn-danger" @click="deleteServer(server)">
            删除服务器
          </button>
        </div>
      </div>
    </div>
    
    <!-- 添加服务器对话框 -->
    <div v-if="showModal" class="modal">
      <div class="modal-content">
        <h2 class="modal-title">添加新攻击服务器</h2>
        
        <div class="form-group">
          <label class="form-label required">服务器名称</label>
          <input v-model="newServer.name" class="form-control" type="text" placeholder="为服务器提供一个描述性名称">
        </div>
        
        <div class="form-group">
          <label class="form-label required">IP地址</label>
          <input v-model="newServer.ip" class="form-control" type="text" placeholder="服务器IP地址">
        </div>
        
        <div class="form-group">
          <label class="form-label">API端口 (可选)</label>
          <input v-model="newServer.port" class="form-control" type="number" placeholder="默认: 31457">
          <span class="hint">客户端代理的监听端口，默认为31457</span>
        </div>
        
        <div class="form-group">
          <label class="form-label required">API密钥</label>
          <div class="api-key-input">
            <input v-model="newServer.apiKey" class="form-control" :type="showApiKey ? 'text' : 'password'" placeholder="安全的API密钥">
            <button class="toggle-visibility" @click="showApiKey = !showApiKey">
              <i :class="showApiKey ? 'el-icon-view' : 'el-icon-hide'"></i>
            </button>
          </div>
          <span class="hint">此密钥用于验证攻击代理的身份，请使用强密码</span>
          <button class="generate-btn" @click="generateApiKey">生成安全密钥</button>
        </div>
        
        <div class="form-group">
          <label class="form-label required">管理员令牌</label>
          <input v-model="adminToken" class="form-control" type="password" placeholder="验证管理员身份">
          <span class="hint">需要管理员令牌来授权添加新的攻击服务器</span>
        </div>
        
        <div class="modal-actions">
          <button @click="closeModal" class="btn btn-secondary">取消</button>
          <button @click="addServer" class="btn btn-primary" :disabled="!isFormValid">添加服务器</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import { mapGetters } from 'vuex'

export default {
  name: 'Servers',
  data() {
    return {
      showModal: false,
      newServer: {
        name: '',
        ip: '',
        port: 31457,
        apiKey: ''
      },
      showApiKey: false,
      adminToken: '',
      apiBaseUrl: process.env.VUE_APP_API_URL || window.location.origin
    }
  },
  computed: {
    ...mapGetters(['allServers', 'onlineServers']),
    
    servers() {
      return this.allServers
    },
    
    totalServers() {
      return this.servers.length
    },
    
    totalCapacity() {
      return this.onlineServers.reduce((sum, server) => sum + (server.packetsRate || 0), 0)
    },
    
    isFormValid() {
      return (
        this.newServer.name.trim() !== '' &&
        this.newServer.ip.trim() !== '' &&
        this.newServer.apiKey.trim() !== '' &&
        this.adminToken.trim() !== ''
      )
    }
  },
  mounted() {
    this.$store.dispatch('loadServers')
  },
  methods: {
    formatNumber(num) {
      return num ? num.toLocaleString() : '0'
    },
    
    formatLastSeen(timestamp) {
      if (!timestamp) return '从未'
      
      const date = new Date(timestamp)
      const now = new Date()
      const diffMs = now - date
      
      // 如果小于1分钟
      if (diffMs < 60000) {
        return '刚刚'
      }
      
      // 如果小于1小时
      if (diffMs < 3600000) {
        const minutes = Math.floor(diffMs / 60000)
        return `${minutes}分钟前`
      }
      
      // 如果小于24小时
      if (diffMs < 86400000) {
        const hours = Math.floor(diffMs / 3600000)
        return `${hours}小时前`
      }
      
      // 否则显示完整日期时间
      return date.toLocaleString()
    },
    
    showAddServerModal() {
      this.showModal = true
      // 重置表单
      this.newServer = {
        name: '',
        ip: '',
        port: 31457,
        apiKey: ''
      }
      this.adminToken = ''
      this.showApiKey = false
    },
    
    closeModal() {
      this.showModal = false
    },
    
    generateApiKey() {
      // 生成32字符的随机密钥
      const characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*'
      let result = ''
      const length = 32
      
      for (let i = 0; i < length; i++) {
        result += characters.charAt(Math.floor(Math.random() * characters.length))
      }
      
      this.newServer.apiKey = result
      this.showApiKey = true
    },
    
    getServerKey(server) {
      // 在实际应用中，这里应该返回加密后的密钥或占位符
      // 为了演示，这里返回一个占位符
      return '********-****-****-****-************'
    },
    
    copySetupCommand(server) {
      // 构建完整的命令
      const command = `cd /path/to/attack-platform/bin\nsudo ./attack-agent -id ${server.id} -key ${this.getServerKey(server)} -master ${this.apiBaseUrl}`
      
      // 复制到剪贴板
      navigator.clipboard.writeText(command)
        .then(() => {
          this.$message.success('命令已复制到剪贴板')
        })
        .catch(err => {
          console.error('复制失败:', err)
          this.$message.error('复制失败，请手动复制')
        })
    },
    
    addServer() {
      if (!this.isFormValid) {
        this.$message.warning('请填写所有必填字段')
        return
      }
      
      const serverData = {
        ...this.newServer,
        adminToken: this.adminToken
      }
      
      this.$store.dispatch('addServer', serverData)
        .then(() => {
          this.$message.success('服务器添加成功')
          this.showModal = false
        })
        .catch(error => {
          this.$message.error('添加服务器失败: ' + error.message)
        })
    },
    
    deleteServer(server) {
      this.$confirm(`确定要删除服务器 "${server.name}" 吗？此操作无法撤销。`, '删除确认', {
        confirmButtonText: '确定删除',
        cancelButtonText: '取消',
        type: 'warning'
      }).then(() => {
        this.$store.dispatch('deleteServer', server.id)
          .then(() => {
            this.$message.success('服务器已删除')
          })
          .catch(error => {
            this.$message.error('删除服务器失败: ' + error.message)
          })
      }).catch(() => {
        // 用户取消删除
      })
    },
    
    useServer(server) {
      if (server.status === 'online') {
        this.$router.push({ 
          name: 'AttackConfig', 
          query: { serverId: server.id } 
        })
      }
    }
  }
}
</script>

<style scoped>
.servers-page {
  max-width: 1200px;
  margin: 0 auto;
  padding-bottom: 40px;
}

.page-description {
  margin-bottom: 20px;
  color: #606266;
}

.stats-card {
  display: flex;
  margin-bottom: 20px;
}

.stat-item {
  flex: 1;
  display: flex;
  align-items: center;
  padding: 15px;
}

.stat-icon {
  width: 60px;
  height: 60px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-right: 15px;
  font-size: 24px;
}

.online-icon {
  background-color: rgba(76, 175, 80, 0.1);
  color: #4CAF50;
}

.offline-icon {
  background-color: rgba(244, 67, 54, 0.1);
  color: #F44336;
}

.capacity-icon {
  background-color: rgba(33, 150, 243, 0.1);
  color: #2196F3;
}

.stat-content {
  flex: 1;
}

.stat-title {
  font-size: 14px;
  color: #909399;
  margin-bottom: 5px;
}

.stat-value {
  font-size: 24px;
  font-weight: bold;
}

.actions-bar {
  display: flex;
  justify-content: flex-end;
  margin-bottom: 20px;
}

.empty-state {
  text-align: center;
  padding: 40px 20px;
}

.empty-icon {
  font-size: 48px;
  color: #909399;
  margin-bottom: 15px;
}

.empty-state h3 {
  margin-top: 0;
  margin-bottom: 10px;
  font-size: 18px;
}

.empty-state p {
  color: #606266;
  margin-bottom: 20px;
}

.servers-container {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
  gap: 20px;
}

.server-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 15px;
  border-bottom: 1px solid #eee;
}

.server-name {
  font-weight: bold;
  font-size: 18px;
}

.status-badge {
  font-size: 12px;
  padding: 4px 8px;
  border-radius: 12px;
  color: white;
}

.status-badge.online {
  background-color: #4CAF50;
}

.status-badge.offline {
  background-color: #F44336;
}

.server-body {
  padding: 15px;
}

.server-info {
  margin-bottom: 20px;
}

.info-row {
  display: flex;
  margin-bottom: 10px;
}

.info-label {
  width: 100px;
  color: #909399;
  display: flex;
  align-items: center;
}

.info-label i {
  margin-right: 5px;
}

.info-value {
  flex: 1;
  font-weight: 500;
}

.server-setup {
  background-color: #f8f8f8;
  border-radius: 4px;
  padding: 15px;
}

.server-setup h3 {
  margin-top: 0;
  margin-bottom: 10px;
  font-size: 16px;
}

.setup-instructions p {
  margin-bottom: 10px;
}

.code-block {
  background-color: #333;
  color: #f8f8f8;
  padding: 15px;
  border-radius: 4px;
  position: relative;
  overflow: auto;
  margin-bottom: 10px;
}

.code-block code {
  font-family: monospace;
  white-space: pre;
  display: block;
}

.copy-btn {
  position: absolute;
  top: 5px;
  right: 5px;
  background-color: #555;
  color: white;
  border: none;
  border-radius: 4px;
  padding: 4px 8px;
  font-size: 12px;
  cursor: pointer;
}

.note {
  font-size: 12px;
  color: #E6A23C;
  font-style: italic;
}

.server-actions {
  display: flex;
  justify-content: flex-end;
  padding: 15px;
  border-top: 1px solid #eee;
}

.server-actions button {
  margin-left: 10px;
}

.btn-disabled {
  background-color: #909399;
  opacity: 0.6;
  cursor: not-allowed;
}

/* 对话框样式 */
.modal {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background-color: rgba(0, 0, 0, 0.5);
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 9999;
}

.modal-content {
  background-color: white;
  border-radius: 8px;
  width: 500px;
  max-width: 90%;
  padding: 25px;
}

.modal-title {
  margin-top: 0;
  margin-bottom: 20px;
  color: #303133;
}

.form-label {
  display: block;
  margin-bottom: 8px;
  font-weight: bold;
}

.form-label.required:after {
  content: '*';
  color: #F56C6C;
  margin-left: 4px;
}

.form-control {
  width: 100%;
  padding: 10px;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 14px;
}

.api-key-input {
  display: flex;
  position: relative;
}

.toggle-visibility {
  position: absolute;
  right: 10px;
  top: 50%;
  transform: translateY(-50%);
  background: none;
  border: none;
  color: #909399;
  cursor: pointer;
}

.generate-btn {
  margin-top: 10px;
  background-color: #409EFF;
  color: white;
  border: none;
  border-radius: 4px;
  padding: 8px 15px;
  font-size: 14px;
  cursor: pointer;
}

.hint {
  display: block;
  font-size: 12px;
  color: #909399;
  margin-top: 4px;
}

.modal-actions {
  display: flex;
  justify-content: flex-end;
  margin-top: 25px;
}

.modal-actions button {
  margin-left: 10px;
}
</style> 