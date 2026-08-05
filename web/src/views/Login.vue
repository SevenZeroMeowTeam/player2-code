<template>
  <div class="login-wrap">
    <el-card class="login-card">
      <template #header>
        <h2 style="margin:0; text-align:center;">
          <el-icon :size="28" color="#409eff"><Cpu /></el-icon>
          Player2 AI 控制台
        </h2>
        <p style="text-align:center; color:#888; margin:8px 0 0;">player.qlm.org.cn</p>
      </template>
      <el-form :model="form" label-position="top" @submit.prevent>
        <el-form-item label="用户名">
          <el-input v-model="form.username" placeholder="admin" size="large">
            <template #prefix><el-icon><User /></el-icon></template>
          </el-input>
        </el-form-item>
        <el-form-item label="密码">
          <el-input v-model="form.password" type="password" placeholder="admin123" size="large" show-password @keyup.enter="doLogin">
            <template #prefix><el-icon><Lock /></el-icon></template>
          </el-input>
        </el-form-item>
        <el-button type="primary" size="large" style="width:100%" :loading="loading" @click="doLogin">登录</el-button>
        <div class="tip">
          <el-alert type="info" :closable="false" show-icon>
            默认账号: admin / admin123
          </el-alert>
        </div>
      </el-form>
    </el-card>
  </div>
</template>

<script setup>
import { reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import axios from 'axios'
import { useSocketStore } from '../stores/socket'

const router = useRouter()
const socket = useSocketStore()
const form = reactive({ username: 'admin', password: 'admin123' })
const loading = ref(false)

async function doLogin() {
  loading.value = true
  try {
    const resp = await axios.post('/api/v1/auth/login', form)
    localStorage.setItem('token', resp.data.token)
    localStorage.setItem('user', JSON.stringify(resp.data))
    socket.connect(resp.data.token)
    ElMessage.success('登录成功')
    router.push('/')
  } catch (e) {
    ElMessage.error(e.response?.data?.error || '登录失败')
  } finally { loading.value = false }
}
</script>

<style scoped>
.login-wrap { min-height: 100vh; display:flex; align-items:center; justify-content:center; background: linear-gradient(135deg, #409eff1a, #67c23a1a); }
.login-card { width: 400px; }
.tip { margin-top: 20px; }
</style>
