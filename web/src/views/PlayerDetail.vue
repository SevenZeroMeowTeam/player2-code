<template>
  <el-container style="height:100vh;">
    <el-header style="display:flex; align-items:center; gap:12px; background:#fff; border-bottom:1px solid #eee;">
      <el-button @click="router.back()" :icon="ArrowLeft" circle />
      <h3 style="margin:0;">玩家详情: {{ playerId }}</h3>
    </el-header>
    <el-main>
      <el-row :gutter="20">
        <el-col :span="8">
          <el-card>
            <template #header><span>AI 决策推理</span></template>
            <div v-if="!decisions.length" style="color:#888; text-align:center; padding:20px;">暂无数据</div>
            <div v-for="(d, idx) in decisions.slice(-20).reverse()" :key="idx" style="margin-bottom:14px;">
              <div style="font-size:11px; color:#888;">{{ new Date(d.ts).toLocaleString() }}</div>
              <div style="background:#409eff1a; padding:8px 10px; border-radius:4px; margin-top:4px;">
                🧠 {{ d.decision.reasoning || '(无)' }}
              </div>
              <div v-for="(a, i) in d.decision.actions || []" :key="i" style="padding:4px 10px; color:#444; font-size:12px; border-left:2px solid #67c23a; margin-top:4px;">
                [{{ a.type }}] {{ JSON.stringify(a) }}
              </div>
            </div>
          </el-card>
        </el-col>
        <el-col :span="8">
          <el-card>
            <template #header><span>聊天记录</span></template>
            <div v-if="!chats.length" style="color:#888; text-align:center; padding:20px;">暂无聊天</div>
            <div v-for="(c, idx) in chats.slice(-50)" :key="idx" style="margin-bottom:10px;">
              <el-tag size="small" :type="c.sender === playerId ? 'success' : 'primary'">{{ c.sender }}</el-tag>
              <span style="margin-left:6px;">{{ c.message }}</span>
              <div v-if="c.reply" style="padding-left:40px; color:#67c23a;">↳ {{ c.reply }}</div>
            </div>
          </el-card>
        </el-col>
        <el-col :span="8">
          <el-card>
            <template #header><span>当前状态</span></template>
            <div style="color:#888;text-align:center;padding:20px;">
              等待 Mod/Bridge 上报感知数据...
            </div>
          </el-card>
        </el-col>
      </el-row>
    </el-main>
  </el-container>
</template>

<script setup>
import { useRoute, useRouter } from 'vue-router'
import { computed } from 'vue'
import { useSocketStore } from '../stores/socket'
import { ArrowLeft } from '@element-plus/icons-vue'

const route = useRoute()
const router = useRouter()
const socket = useSocketStore()
const playerId = computed(() => route.params.id)
const data = computed(() => socket.players.get(playerId.value) || { decisions: [], chats: [], perceptions: [] })
const decisions = computed(() => data.value.decisions || [])
const chats = computed(() => data.value.chats || [])
</script>
