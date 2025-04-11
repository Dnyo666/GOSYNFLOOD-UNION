<template>
  <div class="app-header">
    <div class="logo">
      <h1>攻击管理平台</h1>
    </div>
    <div class="nav-links">
      <router-link to="/" class="nav-item" exact>
        <i class="el-icon-monitor"></i> 仪表盘
      </router-link>
      <router-link to="/servers" class="nav-item">
        <i class="el-icon-s-platform"></i> 服务器管理
      </router-link>
      <router-link to="/attack" class="nav-item">
        <i class="el-icon-s-promotion"></i> 发起攻击
      </router-link>
    </div>
    <div class="user-info">
      <span class="server-status">
        <i class="el-icon-connection"></i>
        在线服务器: {{ activeServers }}/{{ totalServers }}
      </span>
      <span class="attack-status" v-if="activeAttacks > 0">
        <i class="el-icon-warning"></i>
        正在进行的攻击: {{ activeAttacks }}
      </span>
    </div>
  </div>
</template>

<script>
import { mapGetters } from 'vuex'

export default {
  name: 'AppHeader',
  computed: {
    ...mapGetters([
      'activeServers', 
      'totalServers', 
      'activeAttacks'
    ])
  }
}
</script>

<style scoped>
.app-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  height: 60px;
  background-color: #333;
  color: white;
  padding: 0 20px;
}

.logo h1 {
  margin: 0;
  font-size: 20px;
}

.nav-links {
  display: flex;
}

.nav-item {
  color: white;
  text-decoration: none;
  padding: 0 15px;
  height: 60px;
  display: flex;
  align-items: center;
  transition: background-color 0.3s;
}

.nav-item:hover, .router-link-active {
  background-color: #4a4a4a;
}

.nav-item i {
  margin-right: 5px;
}

.user-info {
  display: flex;
  align-items: center;
}

.server-status, .attack-status {
  font-size: 14px;
  margin-left: 15px;
}

.attack-status {
  color: #F56C6C;
  animation: blink 2s infinite;
}

@keyframes blink {
  0% { opacity: 1; }
  50% { opacity: 0.5; }
  100% { opacity: 1; }
}
</style> 