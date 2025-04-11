import Vue from 'vue'
import Vuex from 'vuex'
import { serverApi, attackApi, wsService } from '../api/services'

Vue.use(Vuex)

export default new Vuex.Store({
  state: {
    // 服务器状态
    servers: [],
    activeServers: 0,
    totalServers: 0,
    
    // 攻击任务状态
    attacks: [],
    activeAttacks: 0,
    
    // 统计信息
    totalPackets: 0,
    avgPacketRate: 0,
    
    // WebSocket连接
    wsConnected: false
  },
  
  mutations: {
    // 服务器相关mutations
    SET_SERVERS(state, servers) {
      state.servers = servers
      state.totalServers = servers.length
      state.activeServers = servers.filter(s => s.status === 'online').length
    },
    
    ADD_SERVER(state, server) {
      state.servers.push(server)
      state.totalServers = state.servers.length
    },
    
    UPDATE_SERVER(state, updatedServer) {
      const index = state.servers.findIndex(s => s.id === updatedServer.id)
      if (index !== -1) {
        state.servers.splice(index, 1, updatedServer)
        state.activeServers = state.servers.filter(s => s.status === 'online').length
      }
    },
    
    REMOVE_SERVER(state, serverId) {
      state.servers = state.servers.filter(s => s.id !== serverId)
      state.totalServers = state.servers.length
      state.activeServers = state.servers.filter(s => s.status === 'online').length
    },
    
    // 攻击任务相关mutations
    SET_ATTACKS(state, attacks) {
      state.attacks = attacks
      state.activeAttacks = attacks.filter(a => a.status === 'running').length
    },
    
    ADD_ATTACK(state, attack) {
      state.attacks.push(attack)
      if (attack.status === 'running') {
        state.activeAttacks++
      }
    },
    
    UPDATE_ATTACK(state, updatedAttack) {
      const index = state.attacks.findIndex(a => a.id === updatedAttack.id)
      if (index !== -1) {
        // 检查状态变化
        const oldStatus = state.attacks[index].status
        const newStatus = updatedAttack.status
        
        state.attacks.splice(index, 1, updatedAttack)
        
        // 更新活动攻击计数
        if (oldStatus !== 'running' && newStatus === 'running') {
          state.activeAttacks++
        } else if (oldStatus === 'running' && newStatus !== 'running') {
          state.activeAttacks--
        }
      }
    },
    
    UPDATE_ATTACK_STATS(state, { id, packets, rate }) {
      const attack = state.attacks.find(a => a.id === id)
      if (attack) {
        attack.totalPacketsSent = packets
        attack.currentRate = rate
      }
      
      // 更新全局统计
      state.totalPackets = state.attacks.reduce((sum, a) => sum + (a.totalPacketsSent || 0), 0)
      
      // 计算平均发包率
      const runningAttacks = state.attacks.filter(a => a.status === 'running')
      if (runningAttacks.length > 0) {
        state.avgPacketRate = Math.floor(
          runningAttacks.reduce((sum, a) => sum + (a.currentRate || 0), 0) / runningAttacks.length
        )
      } else {
        state.avgPacketRate = 0
      }
    },
    
    // WebSocket状态
    SET_WS_CONNECTED(state, status) {
      state.wsConnected = status
    }
  },
  
  actions: {
    // 初始化WebSocket连接
    initWebSocket({ commit, dispatch }) {
      wsService.connect(
        // 消息处理
        (data) => {
          // 根据消息类型分发相应的action
          switch (data.type) {
            case 'initial_state':
              if (data.servers) commit('SET_SERVERS', data.servers)
              if (data.attacks) commit('SET_ATTACKS', data.attacks)
              break
              
            case 'server_added':
              commit('ADD_SERVER', data.server)
              break
              
            case 'server_updated':
              commit('UPDATE_SERVER', data.server)
              break
              
            case 'server_deleted':
              commit('REMOVE_SERVER', data.id)
              break
              
            case 'attack_created':
              commit('ADD_ATTACK', data.attack)
              break
              
            case 'attack_started':
              commit('UPDATE_ATTACK', data.attack)
              break
              
            case 'attack_stopped':
              commit('UPDATE_ATTACK', data.attack)
              break
              
            case 'attack_stats_update':
              commit('UPDATE_ATTACK_STATS', {
                id: data.id,
                packets: data.packets,
                rate: data.rate
              })
              break
          }
        },
        // 错误处理
        (error) => {
          console.error('WebSocket错误', error)
          commit('SET_WS_CONNECTED', false)
        }
      )
      
      commit('SET_WS_CONNECTED', true)
    },
    
    // 加载服务器列表
    async loadServers({ commit }) {
      try {
        const servers = await serverApi.getServers()
        commit('SET_SERVERS', servers)
        return servers
      } catch (error) {
        console.error('加载服务器列表失败', error)
        throw error
      }
    },
    
    // 添加服务器
    async addServer({ commit }, server) {
      try {
        const newServer = await serverApi.addServer(server)
        commit('ADD_SERVER', newServer)
        return newServer
      } catch (error) {
        console.error('添加服务器失败', error)
        throw error
      }
    },
    
    // 删除服务器
    async deleteServer({ commit }, serverId) {
      try {
        await serverApi.deleteServer(serverId)
        commit('REMOVE_SERVER', serverId)
      } catch (error) {
        console.error('删除服务器失败', error)
        throw error
      }
    },
    
    // 加载攻击任务列表
    async loadAttacks({ commit }) {
      try {
        const attacks = await attackApi.getAttacks()
        commit('SET_ATTACKS', attacks)
        return attacks
      } catch (error) {
        console.error('加载攻击任务列表失败', error)
        throw error
      }
    },
    
    // 创建攻击任务
    async createAttack({ commit }, attack) {
      try {
        const newAttack = await attackApi.createAttack(attack)
        commit('ADD_ATTACK', newAttack)
        return newAttack
      } catch (error) {
        console.error('创建攻击任务失败', error)
        throw error
      }
    },
    
    // 停止攻击任务
    async stopAttack({ commit }, attackId) {
      try {
        await attackApi.stopAttack(attackId)
        // 实际更新将通过WebSocket接收
      } catch (error) {
        console.error('停止攻击任务失败', error)
        throw error
      }
    }
  },
  
  getters: {
    // 获取所有服务器
    allServers: state => state.servers,
    
    // 获取在线服务器
    onlineServers: state => state.servers.filter(s => s.status === 'online'),
    
    // 通过ID获取服务器
    serverById: state => id => state.servers.find(s => s.id === id),
    
    // 获取所有攻击任务
    allAttacks: state => state.attacks,
    
    // 获取活动攻击任务
    activeAttackList: state => state.attacks.filter(a => a.status === 'running'),
    
    // 获取服务器状态统计
    serverStats: state => ({
      total: state.totalServers,
      active: state.activeServers,
      offline: state.totalServers - state.activeServers
    }),
    
    // 获取攻击统计
    attackStats: state => ({
      total: state.attacks.length,
      active: state.activeAttacks,
      totalPackets: state.totalPackets,
      avgRate: state.avgPacketRate
    }),
    
    // 获取服务器数量
    totalServers: state => state.totalServers,
    
    // 获取在线服务器数量
    activeServers: state => state.activeServers,
    
    // 获取活动攻击数量
    activeAttacks: state => state.activeAttacks,
    
    // 获取总发包数
    totalPackets: state => state.totalPackets,
    
    // 获取平均发包率
    avgPacketRate: state => state.avgPacketRate
  }
}) 