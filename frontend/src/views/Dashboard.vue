<template>
  <div class="dashboard">
    <h1 class="page-title">攻击控制中心</h1>
    
    <!-- 状态卡片 -->
    <div class="stats-cards">
      <div class="card stat-card">
        <div class="stat-icon online-icon">
          <i class="el-icon-s-platform"></i>
        </div>
        <div class="stat-content">
          <div class="stat-title">在线服务器</div>
          <div class="stat-value">{{ activeServers }}/{{ totalServers }}</div>
        </div>
      </div>
      
      <div class="card stat-card">
        <div class="stat-icon attack-icon">
          <i class="el-icon-s-promotion"></i>
        </div>
        <div class="stat-content">
          <div class="stat-title">运行中的攻击</div>
          <div class="stat-value">{{ activeAttacks }}</div>
        </div>
      </div>
      
      <div class="card stat-card">
        <div class="stat-icon packets-icon">
          <i class="el-icon-data-line"></i>
        </div>
        <div class="stat-content">
          <div class="stat-title">总发包数</div>
          <div class="stat-value">{{ formatNumber(totalPackets) }}</div>
        </div>
      </div>
      
      <div class="card stat-card">
        <div class="stat-icon rate-icon">
          <i class="el-icon-data-analysis"></i>
        </div>
        <div class="stat-content">
          <div class="stat-title">当前发包率</div>
          <div class="stat-value">{{ formatNumber(avgPacketRate) }} 包/秒</div>
        </div>
      </div>
    </div>

    <!-- 操作引导卡片 -->
    <div class="card guide-card" v-if="totalServers === 0">
      <div class="guide-icon">
        <i class="el-icon-s-platform"></i>
      </div>
      <div class="guide-content">
        <h3>首先添加攻击服务器</h3>
        <p>您需要先添加攻击服务器，然后才能发起分布式攻击。</p>
        <router-link to="/servers" class="btn btn-primary">立即添加服务器</router-link>
      </div>
    </div>

    <div class="card guide-card" v-else-if="activeServers === 0">
      <div class="guide-icon warning">
        <i class="el-icon-warning"></i>
      </div>
      <div class="guide-content">
        <h3>没有可用的攻击服务器</h3>
        <p>您已添加了攻击服务器，但目前没有服务器处于在线状态。请确保您的攻击代理已启动并配置正确。</p>
      </div>
    </div>

    <div class="card guide-card" v-else-if="activeAttacks === 0">
      <div class="guide-icon success">
        <i class="el-icon-s-promotion"></i>
      </div>
      <div class="guide-content">
        <h3>准备就绪，可以发起攻击</h3>
        <p>您的攻击服务器已准备就绪，现在可以发起分布式攻击。</p>
        <router-link to="/attack" class="btn btn-primary">开始新的攻击</router-link>
      </div>
    </div>
    
    <!-- 主要内容区 -->
    <div class="dashboard-content" v-if="activeServers > 0">
      <!-- 在线服务器 -->
      <div class="card" v-if="onlineServers.length > 0">
        <h2 class="section-title">在线服务器 ({{ onlineServers.length }})</h2>
        <div class="online-servers">
          <div v-for="server in onlineServers" :key="server.id" class="server-item">
            <div class="server-info">
              <div class="server-name">{{ server.name }}</div>
              <div class="server-ip">{{ server.ip }}</div>
            </div>
            <div class="server-stats">
              <div class="stat">
                <span class="label">发包速率:</span>
                <span class="value">{{ formatNumber(server.packetsRate) }} 包/秒</span>
              </div>
            </div>
            <div class="server-actions">
              <router-link :to="{ name: 'AttackConfig', query: { serverId: server.id } }" class="btn btn-primary">
                使用此服务器攻击
              </router-link>
            </div>
          </div>
        </div>
      </div>
      
      <!-- 活动攻击 -->
      <div class="card" v-if="activeAttackList.length > 0">
        <h2 class="section-title">
          运行中的攻击 ({{ activeAttackList.length }})
          <span class="section-subtitle">实时监控</span>
        </h2>
        <div class="active-attacks">
          <div v-for="attack in activeAttackList" :key="attack.id" class="attack-item">
            <div class="attack-header">
              <div class="attack-name">{{ attack.name }}</div>
              <div class="attack-time">已运行: {{ formatDuration(attack.duration) }}</div>
            </div>
            <div class="attack-details">
              <div class="attack-target">
                <i class="el-icon-aim"></i> 目标: {{ attack.targetIp }}:{{ attack.targetPort }}
              </div>
              <div class="attack-servers">
                <i class="el-icon-s-platform"></i> 服务器数量: {{ attack.servers.length }}
              </div>
            </div>
            <div class="attack-progress">
              <div class="progress-row">
                <span class="progress-label">发送包数:</span>
                <span class="progress-value">{{ formatNumber(attack.totalPacketsSent) }}</span>
              </div>
              <div class="progress-row">
                <span class="progress-label">当前速率:</span>
                <span class="progress-value">{{ formatNumber(attack.currentRate) }} 包/秒</span>
              </div>
              <div class="progress-bar" :style="{ width: getAttackIntensity(attack) + '%' }"></div>
            </div>
            <div class="attack-actions">
              <button @click="stopAttack(attack)" class="btn btn-danger">
                <i class="el-icon-circle-close"></i> 停止攻击
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import { mapGetters } from 'vuex'

export default {
  name: 'Dashboard',
  computed: {
    ...mapGetters([
      'onlineServers',
      'allServers',
      'activeAttackList',
      'activeServers',
      'totalServers',
      'activeAttacks',
      'totalPackets',
      'avgPacketRate'
    ])
  },
  methods: {
    formatNumber(num) {
      return num ? num.toLocaleString() : '0'
    },
    formatDuration(seconds) {
      if (!seconds) return '刚刚开始'
      
      const hours = Math.floor(seconds / 3600)
      const minutes = Math.floor((seconds % 3600) / 60)
      const secs = Math.floor(seconds % 60)
      
      let result = []
      if (hours > 0) result.push(`${hours}小时`)
      if (minutes > 0) result.push(`${minutes}分钟`)
      if (secs > 0 || result.length === 0) result.push(`${secs}秒`)
      
      return result.join(' ')
    },
    getAttackIntensity(attack) {
      // 根据攻击速率计算进度条显示百分比
      // 这里假设100万pps是100%强度
      const maxRate = 1000000
      return Math.min(Math.floor((attack.currentRate / maxRate) * 100), 100)
    },
    stopAttack(attack) {
      if (confirm(`确定要停止对 ${attack.targetIp}:${attack.targetPort} 的攻击吗？`)) {
        this.$store.dispatch('stopAttack', attack.id)
          .then(() => {
            this.$message.success('攻击已停止')
          })
          .catch(error => {
            this.$message.error('停止攻击失败: ' + error.message)
          })
      }
    }
  }
}
</script>

<style scoped>
.dashboard {
  padding: 20px 0;
}

.stats-cards {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 20px;
  margin-bottom: 30px;
}

.stat-card {
  display: flex;
  align-items: center;
  padding: 20px;
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

.attack-icon {
  background-color: rgba(244, 67, 54, 0.1);
  color: #F44336;
}

.packets-icon {
  background-color: rgba(33, 150, 243, 0.1);
  color: #2196F3;
}

.rate-icon {
  background-color: rgba(255, 152, 0, 0.1);
  color: #FF9800;
}

.stat-content {
  flex: 1;
}

.stat-title {
  font-size: 14px;
  color: #666;
  margin-bottom: 5px;
}

.stat-value {
  font-size: 24px;
  font-weight: bold;
}

/* 引导卡片样式 */
.guide-card {
  display: flex;
  align-items: center;
  padding: 20px;
  margin-bottom: 30px;
  border-left: 4px solid #4CAF50;
}

.guide-icon {
  width: 60px;
  height: 60px;
  border-radius: 50%;
  background-color: rgba(76, 175, 80, 0.1);
  color: #4CAF50;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-right: 20px;
  font-size: 24px;
}

.guide-icon.warning {
  background-color: rgba(255, 152, 0, 0.1);
  color: #FF9800;
}

.guide-icon.success {
  background-color: rgba(76, 175, 80, 0.1);
  color: #4CAF50;
}

.guide-content {
  flex: 1;
}

.guide-content h3 {
  margin-top: 0;
  margin-bottom: 10px;
}

.guide-content p {
  margin-bottom: 15px;
  color: #666;
  font-size: 14px;
}

/* 服务器列表样式 */
.server-item {
  display: flex;
  align-items: center;
  padding: 15px;
  border-radius: 8px;
  background-color: #f9f9f9;
  margin-bottom: 10px;
}

.server-info {
  flex: 1;
}

.server-name {
  font-weight: bold;
  margin-bottom: 5px;
}

.server-ip {
  font-size: 12px;
  color: #666;
}

.server-stats {
  margin-right: 20px;
}

.server-stats .stat {
  font-size: 14px;
}

.server-stats .label {
  color: #666;
  margin-right: 5px;
}

.server-stats .value {
  font-weight: bold;
}

/* 攻击列表样式 */
.attack-item {
  background-color: #f9f9f9;
  border-radius: 8px;
  padding: 15px;
  margin-bottom: 15px;
}

.attack-header {
  display: flex;
  justify-content: space-between;
  margin-bottom: 10px;
}

.attack-name {
  font-weight: bold;
  font-size: 16px;
}

.attack-time {
  font-size: 12px;
  color: #666;
}

.attack-details {
  display: flex;
  margin-bottom: 15px;
}

.attack-target, .attack-servers {
  margin-right: 20px;
  font-size: 14px;
}

.attack-target i, .attack-servers i {
  margin-right: 5px;
  color: #666;
}

.attack-progress {
  margin-bottom: 15px;
  position: relative;
}

.progress-row {
  display: flex;
  justify-content: space-between;
  margin-bottom: 5px;
  font-size: 14px;
}

.progress-label {
  color: #666;
}

.progress-value {
  font-weight: bold;
}

.progress-bar {
  height: 4px;
  background-color: #4CAF50;
  border-radius: 2px;
  transition: width 0.5s;
}

.attack-actions {
  display: flex;
  justify-content: flex-end;
}

.section-subtitle {
  font-size: 12px;
  color: #999;
  font-weight: normal;
  margin-left: 10px;
}
</style> 