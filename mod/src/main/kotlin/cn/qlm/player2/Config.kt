package cn.qlm.player2

import net.minecraftforge.common.ForgeConfigSpec
import net.minecraftforge.fml.ModLoadingContext
import net.minecraftforge.fml.config.ModConfig

object Config {
    private val BUILDER = ForgeConfigSpec.Builder()
    val SPEC: ForgeConfigSpec

    val enabled: ForgeConfigSpec.BooleanValue
    val autoConnect: ForgeConfigSpec.BooleanValue
    val backendWs: ForgeConfigSpec.ConfigValue<String>
    val token: ForgeConfigSpec.ConfigValue<String>
    val perceptionIntervalMs: ForgeConfigSpec.IntValue
    val maxAIPlayers: ForgeConfigSpec.IntValue
    val defaultPersonality: ForgeConfigSpec.ConfigValue<String>

    init {
        BUILDER.push("general")
        enabled = BUILDER.comment("Enable Player2 AI players").define("enabled", true)
        autoConnect = BUILDER.comment("Auto connect to backend on server start").define("autoConnect", false)
        backendWs = BUILDER.comment("Backend WebSocket URL").define("backendWs", "wss://player.qlm.org.cn")
        token = BUILDER.comment("Auth token for backend").define("token", "")
        perceptionIntervalMs = BUILDER.comment("Perception send interval ms").defineInRange("perceptionIntervalMs", 1500, 200, 10000)
        maxAIPlayers = BUILDER.comment("Max AI players per server").defineInRange("maxAIPlayers", 10, 1, 100)
        defaultPersonality = BUILDER.comment("Default AI personality").define("defaultPersonality", "friendly, hardworking miner")
        BUILDER.pop()
        SPEC = BUILDER.build()
    }

    fun register() {
        ModLoadingContext.get().registerConfig(ModConfig.Type.SERVER, SPEC)
    }
}
