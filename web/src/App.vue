<template>
  <router-view />
</template>

<script setup>
import { useSocketStore } from './stores/socket'
const store = useSocketStore()
import { onMounted } from 'vue'
onMounted(() => {
  const token = localStorage.getItem('token')
  if (token) store.connect(token)
})
</script>
