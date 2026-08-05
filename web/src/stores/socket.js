import { defineStore } from 'pinia'
import { io } from 'socket.io-client'
import { ref, reactive } from 'vue'

export const useSocketStore = defineStore('socket', () => {
  const connected = ref(false)
  const socket = ref(null)
  const players = reactive(new Map())
  const events = ref([])

  function connect(token) {
    if (socket.value?.connected) return
    const host = location.hostname === 'localhost' ? 'ws://localhost:8080' : `wss://${location.host}`
    socket.value = io(host, {
      auth: { token },
      query: { type: 'web' },
      transports: ['websocket']
    })
    socket.value.on('connect', () => { connected.value = true; addEvent('system', '已连接到后端') })
    socket.value.on('disconnect', () => { connected.value = false; addEvent('system', '已断开') })
    socket.value.on('player:created', (p) => addEvent('system', '玩家创建: ' + (p.player?.name || '?')))
    socket.value.on('ai:decision', ({ playerId, decision }) => {
      if (!players.has(playerId)) players.set(playerId, { perceptions: [], decisions: [], chats: [] })
      players.get(playerId).decisions.push({ ts: Date.now(), decision })
    })
    socket.value.on('ai:chat', (c) => {
      if (!players.has(c.playerId)) players.set(c.playerId, { perceptions: [], decisions: [], chats: [] })
      players.get(c.playerId).chats.push(c)
    })
    socket.value.on('mod:event', (e) => addEvent('mod', JSON.stringify(e)))
  }

  function addEvent(type, text) {
    events.value.unshift({ ts: new Date().toLocaleTimeString(), type, text })
    if (events.value.length > 200) events.value.length = 200
  }

  function send(type, data) {
    if (socket.value?.connected) socket.value.emit(type, data)
  }

  function disconnect() { socket.value?.disconnect(); socket.value = null; connected.value = false }

  return { connected, socket, players, events, connect, disconnect, send, addEvent }
})
