package cn.qlm.player2.manager

import cn.qlm.player2.Player2Mod
import com.mojang.authlib.GameProfile
import net.minecraft.server.MinecraftServer
import net.minecraft.server.level.ServerLevel
import net.minecraft.server.level.ServerPlayer
import net.minecraftforge.common.util.FakePlayer
import net.minecraftforge.common.util.FakePlayerFactory
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

object FakePlayerManager {

    lateinit var server: MinecraftServer
    private val aiPlayers = ConcurrentHashMap<String, FakePlayer>()

    fun create(name: String, level: ServerLevel, uuid: UUID = UUID.randomUUID()): FakePlayer? {
        if (aiPlayers.size >= Config.maxAIPlayers.get()) {
            Player2Mod.LOG.warn("[FakePlayer] Max AI players reached: ${aiPlayers.size}")
            return null
        }
        val profile = GameProfile(uuid, name)
        val player = FakePlayerFactory.get(level, profile)
        aiPlayers[name] = player
        Player2Mod.LOG.info("[FakePlayer] Created $name (uuid=$uuid)")
        return player
    }

    fun remove(name: String): Boolean {
        val p = aiPlayers.remove(name) ?: return false
        p.discard()
        Player2Mod.LOG.info("[FakePlayer] Removed $name")
        return true
    }

    fun get(name: String): FakePlayer? = aiPlayers[name]

    fun list(): Collection<FakePlayer> = aiPlayers.values

    fun shutdown() {
        aiPlayers.values.forEach { it.discard() }
        aiPlayers.clear()
    }
}
