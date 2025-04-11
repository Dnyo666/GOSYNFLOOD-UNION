import Vue from 'vue'
import App from './App.vue'
import router from './router'
import store from './store'
import ElementUI from 'element-ui'
import 'element-ui/lib/theme-chalk/index.css'
import './assets/css/main.css'

// 使用ElementUI组件库
Vue.use(ElementUI, {
  size: 'medium'
})

// 添加全局消息方法
Vue.prototype.$message = ElementUI.Message

Vue.config.productionTip = false

new Vue({
  router,
  store,
  render: h => h(App)
}).$mount('#app') 