import Vue from 'vue'
import VueRouter from 'vue-router'
import Dashboard from '../views/Dashboard.vue'

Vue.use(VueRouter)

const routes = [
  {
    path: '/',
    name: 'Dashboard',
    component: Dashboard
  },
  {
    path: '/attack',
    name: 'AttackConfig',
    component: () => import(/* webpackChunkName: "attack" */ '../views/AttackConfig.vue')
  },
  {
    path: '/servers',
    name: 'Servers',
    component: () => import(/* webpackChunkName: "servers" */ '../views/Servers.vue')
  }
]

const router = new VueRouter({
  mode: 'history',
  base: process.env.BASE_URL,
  routes
})

export default router 