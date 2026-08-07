<template>
  <el-container style="height:100vh;">
    <el-header style="display:flex; align-items:center; gap:12px; background:#fff; border-bottom:1px solid #eee;">
      <el-icon :size="24" color="#409eff"><Cpu /></el-icon>
      <h3 style="margin:0;">Player2 AI 控制台</h3>
      <el-tag :type="socket.connected ? 'success' : 'danger'">{{ socket.connected ? '已连接' : '未连接' }}</el-tag>
      <div style="flex:1"></div>
      <el-button :icon="Refresh" circle @click="dialogVisible = true">创建 NPC</el-button>
      <el-button type="danger" :icon="SwitchButton" @click="logout">退出</el-button>
    </el-header>

    <el-container>
      <el-aside width="360px" style="background:#fafafa; border-right:1px solid #eee; padding:12px;">
        <div style="display:flex; align-items:center; justify-content:space-between; margin:4px 0 12px;">
          <h4 style="margin:0;">NPC 列表</h4>
          <el-button size="small" :icon="Refresh" circle @click="socket.fetchNpcs()" />
        </div>
        <el-empty v-if="!socket.npcList.length" description="暂无 NPC" />
        <el-card
          v-for="n in socket.npcList" :key="n.npc_id"
          style="margin-bottom:10px; cursor:pointer;"
          :body-style="{ padding: '12px' }"
          @click="router.push(`/player/${n.npc_id}`)"
          shadow="hover"
        >
          <div style="display:flex; align-items:center; gap:8px;">
            <el-avatar :size="40" :style="{ background: colorOf(n.npc_id) }">
              {{ (n.name || 'A').slice(0,1).toUpperCase() }}
            </el-avatar>
            <div style="flex:1;">
              <div style="font-weight:bold;">{{ n.name }}</div>
              <el-tag size="small" style="margin-top:4px;">{{ n.short_name }}</el-tag>
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
              <el-statistic title="NPC 数量" :value="socket.npcList.length" />
              <el-divider />
              <el-statistic title="AI 大模型" :value="modelLabel" />
              <el-progress :percentage="socket.connected ? 100 : 0" :status="socket.connected ? 'success' : 'exception'" />
            </el-card>
          </el-col>
          <el-col :span="12">
            <el-card>
              <template #header>
                <span><el-icon><MessageBox /></el-icon> NPC 对话与控制</span>
              </template>
              <el-form :inline="true" style="margin-bottom:10px;">
                <el-form-item label="NPC">
                  <el-select v-model="selectedNpc" placeholder="选择 NPC">
                    <el-option v-for="n in socket.npcList" :key="n.npc_id" :label="n.name" :value="n.npc_id" />
                  </el-select>
                </el-form-item>
              </el-form>
              <el-space wrap>
                <el-button type="primary" size="small" @click="cmd('jump')">跳跃</el-button>
                <el-button type="primary" size="small" @click="cmd('move', {direction:'forward', durationMs:1000})">前进</el-button>
                <el-button type="primary" size="small" @click="cmd('move', {direction:'back', durationMs:1000})">后退</el-button>
                <el-button type="success" size="small" @click="cmd('attackNearest', {type:'mob', range:4})">攻击附近怪物</el-button>
                <el-button type="danger" size="small" @click="cmd('stop')">停止</el-button>
                <el-button type="warning" size="small" @click="killNpc">删除 NPC</el-button>
              </el-space>
              <el-divider />
              <el-input
                v-model="chatMsg" placeholder="对 NPC 说话（走官方 /npcs/chat）..." size="small" @keyup.enter="doChat">
                <template #append>
                  <el-button @click="doChat">发送</el-button>
                </template>
              </el-input>
            </el-card>
          </el-col>
        </el-row>

        <el-card style="margin-top:20px;">
          <template #header>
            <span><el-icon><Bell /></el-icon> NPC 响应流（/npcs/responses）</span>
            <el-button size="small" style="float:right" @click="socket.npcResponses.length = 0">清空</el-button>
          </template>
          <div class="log">
            <div v-for="(r, idx) in socket.npcResponses.slice(0, 100)" :key="idx"
                 :style="{ color: r.error ? '#f56c6c' : r.command?.length ? '#67c23a' : '#333'}">
              [{{ new Date(r.ts).toLocaleTimeString() }}] NPC {{ (r.npc_id||'').slice(0,8) }}
              <span v-if="r.message">: {{ r.message }}</span>
              <span v-if="r.command?.length"> | 动作: {{ r.command.map(c=>c.name).join(', ') }}</span>
              <span v-if="r.error"> | 错误: {{ r.error.error_code }} ({{ r.error.error_message }})</span>
            </div>
            <div v-if="!socket.npcResponses.length" style="color:#888;text-align:center;padding:20px;">
              暂无响应，对 NPC 发送消息后将在此显示
            </div>
          </div>
        </el-card>
      </el-main>
    </el-container>

    <el-dialog v-model="dialogVisible" title="创建 NPC（官方 /npcs/spawn）" width="520px">
      <el-form :model="np" label-width="100px">
        <el-form-item label="名字">
          <el-input v-model="np.name" placeholder="AI_Steve" />
        </el-form-item>
        <el-form-item label="短名">
          <el-input v-model="np.short_name" placeholder="Steve（留空则同名字）" />
        </el-form-item>
        <el-form-item label="角色描述">
          <el-input v-model="np.character_description" type="textarea" :rows="2"
            placeholder="一个开朗的老矿工，喜欢探险和聊天" />
        </el-form-item>
        <el-form-item label="系统提示词">
          <el-input v-model="np.system_prompt" type="textarea" :rows="3"
            placeholder="你是 Steve，一名 Minecraft 老玩家。用玩家的口吻简短回复。" />
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
const selectedNpc = ref('')
const chatMsg = ref('')
const np = reactive({
  name: 'AI_' + Math.floor(Math.random() * 9000 + 1000),
  short_name: '',
  character_description: '一个开朗的 Minecraft 玩家，喜欢探险和聊天',
  system_prompt: '你是一名真实的 Minecraft 玩家。用玩家的口吻简短自然地回复，不要透露你是 AI。'
})
const modelLabel = computed(() => 'DeepSeek R1 / Chat')

function colorOf(s) {
  let h = 0; for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) & 0xffff
  return `hsl(${h % 360}, 60%, 60%)`
}

async function createPlayer() {
  try {
    await socket.spawnNpc({
      name: np.name,
      short_name: np.short_name || np.name,
      character_description: np.character_description,
      system_prompt: np.system_prompt
    })
    dialogVisible.value = false
    ElMessage.success('NPC 创建请求已发送')
  } catch (e) { ElMessage.error(e.message) }
}

function cmd(command, params = {}) {
  const npc = socket.npcList.find(n => n.npc_id === selectedNpc.value)
  if (!npc) return ElMessage.warning('请选择 NPC')
  // 直接控制走 Socket.IO（绕过 LLM，立即执行）
  socket.send('player:command', { playerId: npc.bridgePlayerId || npc.name, command, params })
}

async function doChat() {
  if (!selectedNpc.value || !chatMsg.value) return
  try {
    await socket.chatNpc(selectedNpc.value, 'Web控制台', chatMsg.value)
    chatMsg.value = ''
  } catch (e) { ElMessage.error(e.message) }
}

async function killNpc() {
  if (!selectedNpc.value) return
  try {
    await socket.killNpc(selectedNpc.value)
    selectedNpc.value = ''
    ElMessage.success('NPC 已删除')
  } catch (e) { ElMessage.error(e.message) }
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
  max-height: 320px;
  overflow-y: auto;
  background: #fafafa;
  padding: 10px;
  border-radius: 4px;
  line-height: 1.8;
}
</style>
