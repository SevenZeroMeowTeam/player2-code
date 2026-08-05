package cn.qlm.player2

import cn.qlm.player2.network.NetworkChannel
import cn.qlm.player2.bridge.WsBridgeClient
import cn.qlm.player2.manager.FakePlayerManager
import net.minecraftforge.common.MinecraftForge
import net.minecraftforge.event.RegisterCommandsEvent
import net.minecraftforge.event.server.ServerStartingEvent
import net.minecraftforge.event.server.ServerStoppingEvent
import net.minecraftforge.eventbus.api.IEventBus
import net.minecraftforge.eventbus.api.SubscribeEvent
import net.minecraftforge.fml.ModLoadingContext
import net.minecraftforge.fml.common.Mod
import net.minecraftforge.fml.config.ModConfig
import net.minecraftforge.fml.javafmlmod.FMLJavaModLoadingContext
import org.apache.logging.log4j.LogManager
import org.apache.logging.log4j.Logger

@Mod(Player2Mod.MOD_ID)
class Player2Mod {

    init {
        val modEventBus: IEventBus = FMLJavaModLoadingContext.get().modEventBus

        modEventBus.addListener(this::init)
        MinecraftForge.EVENT_BUS.register(this)
    }

    private fun init(event: net.minecraftforge.fml.event.lifecycle.FMLCommonSetupEvent) {
        event.enqueueWork {
            NetworkChannel.init()
            LOG.info("[Player2] Network channel registered")
        }
    }

    @SubscribeEvent
    fun onServerStarting(event: ServerStartingEvent) {
        FakePlayerManager.server = event.server
        if (Config.enabled.get() && Config.autoConnect.get()) {
            WsBridgeClient.connectAsync(
                url = Config.backendWs.get(),
                token = Config.token.get()
            )
        }
        LOG.info("[Player2] Server starting, fake player manager ready")
    }

    @SubscribeEvent
    fun onServerStopping(event: ServerStoppingEvent) {
        WsBridgeClient.disconnect()
        FakePlayerManager.shutdown()
        LOG.info("[Player2] Shutdown complete")
    }

    @SubscribeEvent
    fun onRegisterCommands(event: RegisterCommandsEvent) {
        cn.qlm.player2.command.Player2Commands.register(event.dispatcher)
    }

    companion object {
        const val MOD_ID = "player2"
        val LOG: Logger = LogManager.getLogger(MOD_ID)
    }
}
