<template>
  <el-container style="height:100vh;">
    <el-header style="display:flex; align-items:center; gap:12px; background:#fff; border-bottom:1px solid #eee;">
      <el-button @click="router.back()" :icon="ArrowLeft" circle />
      <h3 style="margin:0;">NPC 详情: {{ npcId.slice(0, 8) }}…</h3>
      <el-button size="small" :icon="Refresh" @click="loadHistory">刷新历史</el-button>
    </el-header>
    <el-main>
      <el-row :gutter="20">
        <el-col :span="12">
          <el-card>
            <template #header><span>对话历史（/npcs/:id/history）</span></template>
            <div v-if="!history.length" style="color:#888; text-align:center; padding:20px;">暂无对话</div>
            <div v-for="(m, idx) in history" :key="idx" style="margin-bottom:12px;">
              <el-tag size="small" :type="m.role === 'user' ? 'primary' : 'success'">{{ m.role }}</el-tag>
              <div style="margin-top:4px; padding:6px 10px; background:#f5f7fa; border-radius:4px;">
                {{ typeof m.content === 'string' ? m.content : JSON.stringify(m.content) }}
              </div>
              <div v-if="m.tool_calls" style="font-size:12px; color:#67c23a; padding-left:10px;">
                ↳ 工具调用: {{ m.tool_calls.map(t => t.function?.name || t.name).join(', ') }}
              </div>
            </div>
          </el-card>
        </el-col>
        <el-col :span="12">
          <el-card>
            <template #header><span>NPC 响应流（/npcs/responses）</span></template>
            <div v-if="!responses.length" style="color:#888; text-align:center; padding:20px;">暂无响应</div>
            <div v-for="(r, idx) in responses.slice(0, 50)" :key="idx" style="margin-bottom:12px;">
              <div style="font-size:11px; color:#888;">{{ new Date(r.ts).toLocaleString() }}</div>
              <div v-if="r.message" style="background:#67c23a1a; padding:8px 10px; border-radius:4px; margin-top:4px;">
                💬 {{ r.message }}
              </div>
              <div v-for="(c, i) in r.command || []" :key="i"
                   style="padding:4px 10px; color:#444; font-size:12px; border-left:2px solid #409eff; margin-top:4px;">
                [{{ c.name }}] {{ c.arguments }}
              </div>
              <div v-if="r.error" style="color:#f56c6c; font-size:12px; margin-top:4px;">
                ⚠ {{ r.error.error_code }}: {{ r.error.error_message }}
              </div>
            </div>
          </el-card>
        </el-col>
      </el-row>
    </el-main>
  </el-container>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useSocketStore } from '../stores/socket'
import { ArrowLeft, Refresh } from '@element-plus/icons-vue'

const route = useRoute()
const router = useRouter()
const socket = useSocketStore()
const npcId = computed(() => route.params.id)
const history = ref([])
const responses = computed(() => socket.npcResponses.filter(r => r.npc_id === npcId.value))

async function loadHistory() {
  history.value = await socket.fetchHistory(npcId.value)
}
onMounted(loadHistory)
</script>
