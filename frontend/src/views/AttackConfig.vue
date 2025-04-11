<template>
  <div class="attack-config">
    <h1 class="page-title">配置攻击任务</h1>
    
    <!-- 如果没有在线服务器，显示警告 -->
    <div class="card warning-card" v-if="onlineServers.length === 0">
      <div class="warning-icon">
        <i class="el-icon-warning"></i>
      </div>
      <div class="warning-content">
        <h3>无可用攻击服务器</h3>
        <p>目前没有在线的攻击服务器。请先添加并确保至少一台服务器在线后再配置攻击。</p>
        <router-link to="/servers" class="btn btn-primary">管理服务器</router-link>
      </div>
    </div>
    
    <!-- 配置表单 -->
    <div class="card config-form" v-else>
      <h2 class="section-title">基本配置</h2>
      
      <div class="form-group">
        <label class="form-label required">攻击名称</label>
        <input v-model="attack.name" class="form-control" type="text" placeholder="为攻击任务提供一个描述性名称">
        <span class="hint">例如：测试目标A的HTTP服务抗压能力</span>
      </div>
      
      <div class="form-row">
        <div class="form-group col">
          <label class="form-label required">目标IP地址</label>
          <input v-model="attack.targetIp" class="form-control" type="text" placeholder="目标IP地址">
        </div>
        
        <div class="form-group col">
          <label class="form-label required">目标端口</label>
          <input v-model="attack.targetPort" class="form-control" type="number" placeholder="目标端口">
          <span class="hint">常见端口: HTTP=80, HTTPS=443</span>
        </div>
      </div>
      
      <h2 class="section-title">攻击设置</h2>
      
      <div class="form-row">
        <div class="form-group col">
          <label class="form-label">持续时间 (秒)</label>
          <input v-model="attack.duration" class="form-control" type="number" placeholder="0表示不限时间">
          <span class="hint">设置为0将持续攻击直到手动停止</span>
        </div>
        
        <div class="form-group col">
          <label class="form-label">每秒数据包限制</label>
          <input v-model="attack.packetsPerSecond" class="form-control" type="number" placeholder="0表示最大速率">
          <span class="hint">限制每秒发送的数据包数量，0表示不限速</span>
        </div>
      </div>
      
      <h2 class="section-title">攻击服务器选择</h2>
      
      <div class="server-selection">
        <div class="selection-header">
          <div class="checkbox-wrapper">
            <input type="checkbox" id="select-all" v-model="selectAll" @change="toggleSelectAll">
            <label for="select-all">全选</label>
          </div>
          <span class="selection-count">已选择 {{ selectedServers.length }}/{{ onlineServers.length }} 台服务器</span>
        </div>
        
        <div class="server-list">
          <div v-for="server in onlineServers" :key="server.id" class="server-item">
            <div class="checkbox-wrapper">
              <input type="checkbox" :id="`server-${server.id}`" v-model="selectedServerIds" :value="server.id">
              <label :for="`server-${server.id}`"></label>
            </div>
            <div class="server-info">
              <div class="server-name">{{ server.name }}</div>
              <div class="server-ip">{{ server.ip }}</div>
            </div>
            <div class="server-stats">
              <div class="stat-item">
                <i class="el-icon-data-line"></i>
                <span>{{ formatNumber(server.packetsRate) }} 包/秒</span>
              </div>
            </div>
          </div>
        </div>
      </div>
      
      <div class="security-check">
        <div class="security-header">
          <i class="el-icon-lock"></i>
          <span>安全验证</span>
        </div>
        <div class="security-content">
          <div class="form-group">
            <label class="form-label required">管理员令牌</label>
            <input v-model="adminToken" class="form-control" type="password" placeholder="输入管理员令牌以授权此攻击">
            <span class="hint">为防止未授权使用，发起攻击需要管理员令牌验证</span>
          </div>
        </div>
      </div>
      
      <div class="confirm-disclaimer">
        <input type="checkbox" id="confirm-legal" v-model="legalConfirmed">
        <label for="confirm-legal">我确认此次攻击已获得明确授权，仅用于安全测试目的</label>
      </div>
      
      <div class="form-actions">
        <button @click="cancel" class="btn btn-secondary">取消</button>
        <button @click="showConfirmation" class="btn btn-primary" :disabled="!isFormValid">
          开始攻击
        </button>
      </div>
    </div>
    
    <!-- 确认对话框 -->
    <div class="modal" v-if="showConfirmModal">
      <div class="modal-content">
        <h2>确认发起攻击</h2>
        <p>您即将对以下目标发起SYN洪水攻击：</p>
        
        <div class="confirm-details">
          <div class="detail-item">
            <div class="detail-label">目标:</div>
            <div class="detail-value">{{ attack.targetIp }}:{{ attack.targetPort }}</div>
          </div>
          <div class="detail-item">
            <div class="detail-label">攻击服务器:</div>
            <div class="detail-value">{{ selectedServers.length }} 台</div>
          </div>
          <div class="detail-item">
            <div class="detail-label">持续时间:</div>
            <div class="detail-value">{{ attack.duration ? `${attack.duration} 秒` : '不限时间' }}</div>
          </div>
        </div>
        
        <div class="warning-message">
          <i class="el-icon-warning"></i>
          <span>警告：此操作可能对目标系统造成严重影响。确保您已获得明确授权。</span>
        </div>
        
        <div class="modal-actions">
          <button @click="showConfirmModal = false" class="btn btn-secondary">取消</button>
          <button @click="startAttack" class="btn btn-danger">
            确认发起攻击
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import { mapGetters } from 'vuex'

export default {
  name: 'AttackConfig',
  data() {
    return {
      attack: {
        name: '',
        targetIp: '',
        targetPort: 80,
        duration: 0,
        packetsPerSecond: 0
      },
      selectedServerIds: [],
      selectAll: false,
      showConfirmModal: false,
      adminToken: '',
      legalConfirmed: false
    }
  },
  computed: {
    ...mapGetters(['onlineServers', 'serverById']),
    
    selectedServers() {
      return this.selectedServerIds.map(id => this.serverById(id)).filter(Boolean)
    },
    
    isFormValid() {
      return (
        this.attack.name.trim() !== '' &&
        this.attack.targetIp.trim() !== '' &&
        this.attack.targetPort > 0 &&
        this.attack.targetPort <= 65535 &&
        this.selectedServers.length > 0 &&
        this.adminToken.trim() !== '' &&
        this.legalConfirmed
      )
    }
  },
  created() {
    // 检查是否有预选的服务器ID
    const serverId = this.$route.query.serverId
    if (serverId) {
      const id = parseInt(serverId)
      if (!isNaN(id) && this.onlineServers.some(s => s.id === id)) {
        this.selectedServerIds = [id]
      }
    }
  },
  methods: {
    formatNumber(num) {
      return num ? num.toLocaleString() : '0'
    },
    
    toggleSelectAll() {
      if (this.selectAll) {
        this.selectedServerIds = this.onlineServers.map(server => server.id)
      } else {
        this.selectedServerIds = []
      }
    },
    
    showConfirmation() {
      if (this.isFormValid) {
        this.showConfirmModal = true
      }
    },
    
    startAttack() {
      const attackConfig = {
        ...this.attack,
        servers: this.selectedServerIds,
        adminToken: this.adminToken
      }
      
      this.$store.dispatch('createAttack', attackConfig)
        .then(() => {
          this.$message.success('攻击任务已成功启动')
          this.showConfirmModal = false
          this.$router.push('/')
        })
        .catch(error => {
          this.$message.error('启动攻击失败: ' + error.message)
          this.showConfirmModal = false
        })
    },
    
    cancel() {
      this.$router.push('/')
    }
  },
  watch: {
    onlineServers: {
      handler(servers) {
        // 更新全选状态
        if (this.selectedServerIds.length === servers.length && servers.length > 0) {
          this.selectAll = true
        } else {
          this.selectAll = false
        }
        
        // 检查是否有离线的服务器被选中，如果有则移除
        this.selectedServerIds = this.selectedServerIds.filter(id => 
          servers.some(server => server.id === id)
        )
      },
      immediate: true
    }
  }
}
</script>

<style scoped>
.attack-config {
  max-width: 900px;
  margin: 0 auto;
  padding-bottom: 40px;
}

.warning-card {
  display: flex;
  align-items: center;
  padding: 20px;
  margin-bottom: 20px;
  border-left: 4px solid #E6A23C;
}

.warning-icon {
  font-size: 36px;
  margin-right: 20px;
  color: #E6A23C;
}

.warning-content h3 {
  margin-top: 0;
  margin-bottom: 10px;
}

.warning-content p {
  margin-bottom: 15px;
}

.config-form {
  padding: 30px;
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

.hint {
  display: block;
  font-size: 12px;
  color: #909399;
  margin-top: 4px;
}

.form-row {
  display: flex;
  margin: 0 -10px;
  margin-bottom: 20px;
}

.form-row .form-group {
  flex: 1;
  padding: 0 10px;
  margin-bottom: 0;
}

.form-group {
  margin-bottom: 20px;
}

/* 服务器选择样式 */
.server-selection {
  border: 1px solid #eee;
  border-radius: 4px;
  margin-bottom: 30px;
}

.selection-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 15px;
  background-color: #f9f9f9;
  border-bottom: 1px solid #eee;
}

.checkbox-wrapper {
  display: flex;
  align-items: center;
}

.checkbox-wrapper label {
  margin-left: 8px;
  cursor: pointer;
}

.selection-count {
  font-size: 14px;
  color: #606266;
}

.server-list {
  max-height: 300px;
  overflow-y: auto;
  padding: 10px;
}

.server-item {
  display: flex;
  align-items: center;
  padding: 12px;
  border-radius: 4px;
  background-color: #f9f9f9;
  margin-bottom: 10px;
}

.server-info {
  flex: 1;
  margin-left: 10px;
}

.server-name {
  font-weight: bold;
  margin-bottom: 5px;
}

.server-ip {
  font-size: 12px;
  color: #909399;
}

.server-stats {
  margin-left: 20px;
}

.stat-item {
  display: flex;
  align-items: center;
  font-size: 14px;
}

.stat-item i {
  margin-right: 5px;
  color: #409EFF;
}

/* 安全验证区域 */
.security-check {
  background-color: #f8f8f8;
  border-radius: 4px;
  padding: 20px;
  margin-bottom: 20px;
}

.security-header {
  display: flex;
  align-items: center;
  margin-bottom: 15px;
  font-weight: bold;
  color: #303133;
}

.security-header i {
  margin-right: 8px;
  color: #409EFF;
}

.confirm-disclaimer {
  display: flex;
  align-items: flex-start;
  margin-bottom: 20px;
}

.confirm-disclaimer label {
  margin-left: 8px;
  line-height: 1.4;
  font-size: 14px;
  color: #606266;
}

.form-actions {
  display: flex;
  justify-content: flex-end;
}

.form-actions button {
  margin-left: 10px;
}

/* 确认对话框 */
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

.modal-content h2 {
  margin-top: 0;
  margin-bottom: 15px;
  color: #303133;
}

.confirm-details {
  background-color: #f5f7fa;
  border-radius: 4px;
  padding: 15px;
  margin: 15px 0;
}

.detail-item {
  display: flex;
  margin-bottom: 8px;
}

.detail-label {
  width: 100px;
  font-weight: bold;
  color: #606266;
}

.warning-message {
  background-color: #fff6f6;
  border: 1px solid #fde2e2;
  color: #f56c6c;
  padding: 10px 15px;
  border-radius: 4px;
  margin: 20px 0;
  display: flex;
  align-items: center;
}

.warning-message i {
  margin-right: 8px;
  font-size: 18px;
}

.modal-actions {
  display: flex;
  justify-content: flex-end;
  margin-top: 20px;
}

.modal-actions button {
  margin-left: 10px;
}

.btn-danger {
  background-color: #F56C6C;
}

.btn-danger:hover {
  background-color: #E64747;
}

/* 按钮禁用状态 */
button:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
</style> 