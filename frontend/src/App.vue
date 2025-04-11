<template>
  <div id="app">
    <app-header />
    <div class="main-content">
      <router-view/>
    </div>
    <div class="app-footer">
      <p>© {{ new Date().getFullYear() }} 攻击管理平台 | 仅供授权的安全测试使用</p>
    </div>
  </div>
</template>

<script>
import AppHeader from './components/AppHeader.vue'

export default {
  name: 'App',
  components: {
    AppHeader
  },
  created() {
    // 初始化WebSocket连接
    this.$store.dispatch('initWebSocket')
    // 加载服务器列表
    this.$store.dispatch('loadServers')
    // 加载攻击任务列表
    this.$store.dispatch('loadAttacks')
  }
}
</script>

<style>
body {
  margin: 0;
  padding: 0;
  font-family: 'Arial', sans-serif;
  background-color: #f5f5f5;
  color: #333;
}

#app {
  width: 100%;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

.main-content {
  flex: 1;
  padding: 20px;
  max-width: 1200px;
  margin: 0 auto;
  width: 100%;
}

.app-footer {
  text-align: center;
  padding: 15px;
  background-color: #333;
  color: #999;
  font-size: 12px;
}

/* 通用样式 */
.card {
  background-color: #fff;
  border-radius: 8px;
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
  padding: 20px;
  margin-bottom: 20px;
}

.section-title {
  border-bottom: 1px solid #eee;
  padding-bottom: 10px;
  margin-top: 0;
  margin-bottom: 20px;
  font-size: 18px;
  color: #333;
}

.page-title {
  margin-bottom: 20px;
  font-size: 24px;
}

/* 按钮样式 */
.btn-primary {
  background-color: #4CAF50;
  color: white;
}

.btn-danger {
  background-color: #f44336;
  color: white;
}

.btn {
  border: none;
  padding: 8px 16px;
  border-radius: 4px;
  cursor: pointer;
}
</style> 