import { defineStore } from 'pinia'
import { io } from 'socket.io-client'
import { ref, reactive } from 'vue'

export const useSocketStore = defineStore('socket', () => {
  const connected = ref(false)
  const socket = ref(null)
  const token = ref('')
  const players = reactive(new Map())
  const events = ref([])
  // 官方 NPC API 相关
  const npcList = ref([])
  const npcResponses = ref([])   // /npcs/responses 流
  let eventSource = null

  // 开发环境直连 backend 8080，生产走 nginx 同源
  const apiBase = location.hostname === 'localhost' ? 'http://localhost:8080' : ''
  const wsBase = location.hostname === 'localhost' ? 'ws://localhost:8080' : `wss://${location.host}`

  function connect(t) {
    token.value = t
    if (socket.value?.connected) return
    socket.value = io(wsBase, {
      auth: { token: t },
      query: { type: 'web' },
      transports: ['websocket']
    })
    socket.value.on('connect', () => {
      connected.value = true
      addEvent('system', '已连接到后端')
      fetchNpcs()
      startResponseStream()
    })
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
    // backend 也会通过 Socket.IO 推送 npc:response（与 SSE 双通道）
    socket.value.on('npc:response', (r) => pushNpcResponse(r))
  }

  function pushNpcResponse(r) {
    npcResponses.value.unshift({ ts: Date.now(), ...r })
    if (npcResponses.value.length > 200) npcResponses.value.length = 200
    const preview = r.message
      ? r.message
      : (r.command && r.command.length ? `${r.command.length} 个动作` : '')
    addEvent('npc', `NPC ${(r.npcId || '').slice(0, 8)}: ${preview || r.error?.error_code || ''}`)
  }

  // ===== 官方 NPC REST API（对齐 player2-sdk-ts）=====
  async function spawnNpc(body) {
    const res = await fetch(`${apiBase}/npcs/spawn`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token.value },
      body: JSON.stringify(body)
    })
    if (!res.ok) throw new Error('spawn failed: ' + res.status)
    const npcId = await res.text()
    await fetchNpcs()
    addEvent('system', `NPC 已创建: ${body.name} (${npcId.slice(0, 8)})`)
    return npcId
  }

  async function chatNpc(npcId, senderName, message, gameStateInfo) {
    const res = await fetch(`${apiBase}/npcs/${npcId}/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token.value },
      body: JSON.stringify({
        sender_name: senderName,
        sender_message: message,
        game_state_info: gameStateInfo || null
      })
    })
    if (!res.ok) throw new Error('chat failed: ' + res.status)
    return res.json()
  }

  async function killNpc(npcId) {
    const res = await fetch(`${apiBase}/npcs/${npcId}/kill`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + token.value }
    })
    if (!res.ok) throw new Error('kill failed: ' + res.status)
    await fetchNpcs()
    addEvent('system', `NPC 已删除: ${npcId.slice(0, 8)}`)
  }

  async function fetchNpcs() {
    try {
      const res = await fetch(`${apiBase}/npcs`, {
        headers: { 'Authorization': 'Bearer ' + token.value }
      })
      if (res.ok) npcList.value = (await res.json()).npcs || []
    } catch (e) { /* ignore */ }
  }

  async function fetchHistory(npcId) {
    const res = await fetch(`${apiBase}/npcs/${npcId}/history`, {
      headers: { 'Authorization': 'Bearer ' + token.value }
    })
    if (!res.ok) return []
    return (await res.json()).history || []
  }

  // ===== /npcs/responses SSE 响应流 =====
  function startResponseStream() {
    stopResponseStream()
    eventSource = new EventSource(`${apiBase}/npcs/responses?token=${encodeURIComponent(token.value)}`)
    eventSource.addEventListener('npc_response', (ev) => {
      try { pushNpcResponse(JSON.parse(ev.data)) } catch (e) { /* ignore */ }
    })
    eventSource.onerror = () => { /* EventSource 自动重连 */ }
  }

  function stopResponseStream() {
    if (eventSource) { eventSource.close(); eventSource = null }
  }

  function addEvent(type, text) {
    events.value.unshift({ ts: new Date().toLocaleTimeString(), type, text })
    if (events.value.length > 200) events.value.length = 200
  }

  function send(type, data) {
    if (socket.value?.connected) socket.value.emit(type, data)
  }

  function disconnect() {
    stopResponseStream()
    socket.value?.disconnect()
    socket.value = null
    connected.value = false
  }

  return {
    connected, socket, players, events, npcList, npcResponses,
    connect, disconnect, send, addEvent,
    spawnNpc, chatNpc, killNpc, fetchNpcs, fetchHistory,
    startResponseStream, stopResponseStream
  }
})
