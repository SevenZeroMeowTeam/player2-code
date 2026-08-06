<template>
  <el-container style="height:100vh;">
    <el-header style="display:flex; align-items:center; gap:12px; background:#fff; border-bottom:1px solid #eee;">
      <el-icon :size="24" color="#409eff"><Cpu /></el-icon>
      <h3 style="margin:0;">Player2 AI 控制台</h3>
      <el-tag :type="socket.connected ? 'success' : 'danger'">{{ socket.connected ? '已连接' : '未连接' }}</el-tag>
      <div style="flex:1"></div>
      <el-button :icon="Refresh" circle @click="dialogVisible = true">创建 AI 玩家</el-button>
      <el-button type="danger" :icon="SwitchButton" @click="logout">退出</el-button>
    </el-header>

    <el-container>
      <el-aside width="360px" style="background:#fafafa; border-right:1px solid #eee; padding:12px;">
        <h4 style="margin:4px 0 12px;">玩家列表</h4>
        <el-empty v-if="!playerList.length === 0" description="暂无 AI 玩家" />
        <el-card
          v-for="p in playerList" :key="p.id"
          style="margin-bottom:10px; cursor:pointer;"
          :body-style="{ padding: '12px' }"
          @click="router.push(`/player/${p.id}`)"
          shadow="hover"
        >
          <div style="display:flex; align-items:center; gap:8px;">
            <el-avatar :size="40" :style="{ background: colorOf(p.id) }">
              {{ (p.name || 'A').slice(0,1).toUpperCase() }}
            </el-avatar>
            <div style="flex:1;">
              <div style="font-weight:bold;">{{ p.name }}</div>
              <el-tag size="small" style="margin-top:4px;">{{ p.serverHost }}:{{ p.serverPort }}</el-tag>
            </div>
            <el-icon :size="18" color="#67c23a"><Monitor /></el-icon>
          </div>
        </el-card>
      </el-aside>

      <el-main style="padding:20px;">
        <el-row :gutter="20">
          <el-col :span="12">
            <el-card>
              <template #header>
                <span><el-icon><DataLine /></el-icon> 系统状态</span>
              </template>
              <el-statistic title="在线 AI 玩家" :value="playerList.length" />
              <el-divider />
              <el-statistic title="AI 大模型" label="ai.bbsmc.org.cn" />
              <el-progress :percentage="socket.connected ? 100 : 0" :status="socket.connected ? 'success' : 'exception'" />
            </el-card>
          </el-col>
          <el-col :span="12">
            <el-card>
              <template #header>
                <span><el-icon><MessageBox /></el-icon> 快速指令</span>
              </template>
              <el-form :inline="true" style="margin-bottom:10px;">
                <el-form-item label="玩家">
                  <el-select v-model="cmdPlayer" placeholder="选择玩家">
                    <el-option v-for="p in playerList" :key="p.id" :label="p.name" :value="p.id" />
                  </el-select>
                </el-form-item>
              </el-form>
              <el-space wrap>
                <el-button type="primary" size="small" @click="cmd('jump')">跳跃</el-button>
                <el-button type="primary" size="small" @click="cmd('move', {direction:'forward', durationMs:1000})">前进</el-button>
                <el-button type="primary" size="small" @click="cmd('move', {direction:'back', durationMs:1000})">后退</el-button>
                <el-button type="primary" size="small" @click="cmd('move', {direction:'left', durationMs:1000})">左移</el-button>
                <el-button type="primary" size="small" @click="cmd('move', {direction:'right', durationMs:1000})">右移</el-button>
                <el-button type="success" size="small" @click="cmd('attackNearest', {type:'mob', range:4})">攻击附近怪物</el-button>
                <el-button type="danger" size="small" @click="cmd('stop')">停止</el-button>
                <el-button type="warning" size="small" @click="cmd('disconnect')">下线</el-button>
              </el-space>
              <el-divider />
              <el-input
                v-model="chatMsg" placeholder="和 AI 聊天..." size="small" @keyup.enter="doChat">
                <template #append>
                  <el-button @click="doChat">发送</el-button>
                </template>
              </el-input>
            </el-card>
          </el-col>
        </el-row>

        <el-card style="margin-top:20px;">
          <template #header>
            <span><el-icon><Bell /></el-icon> 事件日志</span>
            <el-button size="small" style="float:right" @click="socket.events.length = 0">清空</el-button>
          </template>
          <div class="log">
            <div v-for="(e, idx) in socket.events.slice(0, 100)" :key="idx"
                 :style="{ color: e.type==='system' ? '#409eff' : e.type==='mod' ? '#67c23a' : '#333'}">
              [{{ e.ts }}] {{ e.text }}
            </div>
          </div>
        </el-card>
      </el-main>
    </el-container>

    <el-dialog v-model="dialogVisible" title="创建 AI 玩家" width="500px">
      <el-form :model="np" label-width="100px">
        <el-form-item label="玩家名">
          <el-input v-model="np.name" placeholder="AI_Player_01" />
        </el-form-item>
        <el-form-item label="服务器地址">
          <el-input v-model="np.serverHost" placeholder="127.0.0.1" />
        </el-form-item>
        <el-form-item label="端口">
          <el-input-number v-model="np.serverPort" :min="1" :max="65535" />
        </el-form-item>
        <el-form-item label="游戏版本">
          <el-select v-model="np.version">
            <el-option label="1.20.1" value="1.20.1" />
            <el-option label="1.19.4" value="1.19.4" />
            <el-option label="1.18.2" value="1.18.2" />
          </el-select>
        </el-form-item>
        <el-form-item label="性格">
          <el-input v-model="np.personality" type="textarea" :rows="2" placeholder="friendly, hardworking miner, funny..." />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible=false">取消</el-button>
        <el-button type="primary" @click="createPlayer">创建</el-button>
      </template>
    </el-dialog>
  </el-container>
</template>

<script setup>
import { ref, reactive, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useSocketStore } from '../stores/socket'
import { ElMessage } from 'element-plus'
import { Cpu, Refresh, SwitchButton, Monitor, DataLine, MessageBox, Bell } from '@element-plus/icons-vue'

const router = useRouter()
const socket = useSocketStore()
const dialogVisible = ref(false)
const cmdPlayer = ref('')
const chatMsg = ref('')
const np = reactive({
  name: 'AI_Player_' + Math.floor(Math.random()*9000+1000),
  serverHost: '127.0.0.1', serverPort: 25565,
  version: '1.20.1', mode: 'survival',
  personality: 'friendly, hardworking miner'
})

const playerList = computed(() => Array.from(socket.players.entries()).map(([id, v]) => ({ id, ...v })))

function colorOf(s) {
  let h = 0; for (let i=0;i<s.length;i++) h = (h*31 + s.charCodeAt(i)) & 0xffff
  return `hsl(${h % 360}, 60%, 60%)`
}

function createPlayer() {
  socket.send('player:create', { ...np })
  dialogVisible.value = false
  ElMessage.success('已发送创建请求')
}

function cmd(command, params={}) {
  if (!cmdPlayer.value) return ElMessage.warning('请选择玩家')
  socket.send('player:command', { playerId: cmdPlayer.value, command, params })
}

function doChat() {
  if (!cmdPlayer.value || !chatMsg.value) return
  socket.send('player:chat', { playerId: cmdPlayer.value, sender: 'Web控制台', message: chatMsg.value })
  chatMsg.value = ''
}

function logout() {
  localStorage.clear()
  socket.disconnect()
  router.push('/login')
}
</script>

<style scoped>
.log {
  font-family: Consolas, monospace;
  font-size: 12px;
  max-height: 300px;
  overflow-y: auto;
  background: #fafafa;
  padding: 10px;
  border-radius: 4px;
  line-height: 1.8;
}
</style>
