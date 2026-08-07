package cn.qlm.player2.bridge

import cn.qlm.player2.Config
import cn.qlm.player2.Player2Mod
import cn.qlm.player2.manager.ActionExecutor
import cn.qlm.player2.manager.FakePlayerManager
import cn.qlm.player2.manager.PerceptionCollector
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.neovisionaries.ws.client.WebSocket
import com.neovisionaries.ws.client.WebSocketAdapter
import com.neovisionaries.ws.client.WebSocketFactory
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

data class WsMessage(
    val type: String,
    val playerId: String? = null,
    val payload: JsonObject = JsonObject()
)

object WsBridgeClient {

    private val gson = Gson()
    private var ws: WebSocket? = null
    private val executor = Executors.newScheduledThreadPool(2)
    private var perceptionTask: ScheduledFuture<*>? = null
    private var connected = false

    fun connectAsync(url: String, token: String) {
        executor.execute {
            try {
                val factory = WebSocketFactory().setConnectionTimeout(10000)
                val fullUrl = "$url?type=bridge&token=$token"
                ws = factory.createSocket(fullUrl)
                    .addHeader("Authorization", "Bearer $token")
                    .addListener(object : WebSocketAdapter() {
                        override fun onConnected(websocket: WebSocket?, headers: MutableMap<String, MutableList<String>>?) {
                            connected = true
                            Player2Mod.LOG.info("[WS] Connected to $url")
                            startPerceptionLoop()
                        }

                        override fun onTextMessage(websocket: WebSocket?, text: String?) {
                            text ?: return
                            try { handleMessage(text) }
                            catch (t: Throwable) { Player2Mod.LOG.error("[WS Msg Error]", t) }
                        }

                        override fun onDisconnected(websocket: WebSocket?, serverCloseFrame: com.neovisionaries.ws.client.WebSocketFrame?, clientCloseFrame: com.neovisionaries.ws.client.WebSocketFrame?, closedByServer: Boolean) {
                            connected = false
                            Player2Mod.LOG.warn("[WS] Disconnected")
                            perceptionTask?.cancel(true)
                        }

                        override fun onError(websocket: WebSocket?, cause: com.neovisionaries.ws.client.WebSocketException?) {
                            Player2Mod.LOG.error("[WS Error]", cause)
                        }
                    })
                    .connectAsynchronously()
            } catch (t: Throwable) {
                Player2Mod.LOG.error("[WS Connect Failed]", t)
            }
        }
    }

    fun disconnect() {
        try {
            perceptionTask?.cancel(true)
            ws?.disconnect()
        } catch (_: Throwable) {}
        connected = false
    }

    private fun startPerceptionLoop() {
        perceptionTask = executor.scheduleAtFixedRate({
            try {
                for (player in FakePlayerManager.list()) {
                    val p = PerceptionCollector.collect(player, 20)
                    send("perception", mapOf(
                        "playerId" to player.gameProfile.name,
                        "perception" to p
                    ))
                }
            } catch (t: Throwable) { Player2Mod.LOG.error("[Perception]", t) }
        }, 2, Config.perceptionIntervalMs.get().toLong(), TimeUnit.MILLISECONDS)
    }

    fun send(type: String, data: Any) {
        if (!connected || ws == null) return
        try {
            val obj = JsonObject()
            obj.addProperty("type", type)
            obj.add("data", gson.toJsonTree(data))
            ws?.sendText(gson.toJson(obj))
        } catch (t: Throwable) { Player2Mod.LOG.warn("[WS send fail]", t) }
    }

    private fun handleMessage(text: String) {
        val json = JsonParser.parseString(text).asJsonObject
        val type = json.get("type")?.asString ?: return
        val data = json.getAsJsonObject("data") ?: JsonObject()
        val playerId = data.get("playerId")?.asString ?: return
        val player = FakePlayerManager.get(playerId) ?: run {
            Player2Mod.LOG.warn("[WS] Player not found: $playerId")
            return
        }

        when (type) {
            "player:actions" -> {
                val actionsArr = data.getAsJsonArray("actions") ?: return
                val actions = actionsArr.map { gson.fromJson(it, cn.qlm.player2.manager.Action::class.java) }
                ActionExecutor.enqueue(player, actions)
            }
            "player:say" -> {
                val message = data.get("message")?.asString ?: return
                ActionExecutor.enqueue(player, listOf(cn.qlm.player2.manager.Action("chat", message = message)))
            }
            "player:command" -> {
                val cmd = data.get("command")?.asString
                val params = data.getAsJsonObject("params") ?: JsonObject()
                handleDirectCommand(player, cmd, params)
            }
            "player:spawn" -> {
                val name = data.get("name")?.asString ?: return
                FakePlayerManager.create(name, player.level() as net.minecraft.server.level.ServerLevel)
            }
            "mod:event" -> {
                    Player2Mod.LOG.info("[WS Event] ${data}")
            }
            // 官方 NPC 响应：message → 假玩家说话；command[] → FunctionCall 转为 Action 执行
            "npc:response" -> {
                val message = data.get("message")?.asString
                val commandArr = data.getAsJsonArray("command")
                if (!message.isNullOrEmpty()) {
                    ActionExecutor.enqueue(player, listOf(cn.qlm.player2.manager.Action("chat", message = message)))
                }
                if (commandArr != null) {
                    val actions = commandArr.mapNotNull { el ->
                        val fc = el.asJsonObject
                        val name = fc.get("name")?.asString ?: return@mapNotNull null
                        val argsStr = fc.get("arguments")?.asString ?: "{}"
                        val args = try { JsonParser.parseString(argsStr).asJsonObject } catch (_: Throwable) { JsonObject() }
                        functionCallToAction(name, args)
                    }
                    if (actions.isNotEmpty()) ActionExecutor.enqueue(player, actions)
                }
            }
            // NPC 被删除：移除假玩家
            "player:kill" -> {
                FakePlayerManager.remove(playerId)
            }
        }
    }

    private fun handleDirectCommand(p: net.minecraft.world.entity.player.Player, cmd: String?, params: JsonObject) {
        val a = when (cmd) {
            "chat" -> cn.qlm.player2.manager.Action("chat", message = params.get("message")?.asString)
            "lookAt" -> cn.qlm.player2.manager.Action("lookAt",
                x = params.get("x")?.asDouble, y = params.get("y")?.asDouble, z = params.get("z")?.asDouble)
            "move" -> cn.qlm.player2.manager.Action("move",
                direction = params.get("direction")?.asString,
                durationMs = params.get("durationMs")?.asLong ?: 300)
            "jump" -> cn.qlm.player2.manager.Action("jump")
            "stop" -> cn.qlm.player2.manager.Action("stop")
            "break" -> cn.qlm.player2.manager.Action("break",
                x = params.get("x")?.asDouble, y = params.get("y")?.asDouble, z = params.get("z")?.asDouble)
            "place" -> cn.qlm.player2.manager.Action("place",
                x = params.get("x")?.asDouble, y = params.get("y")?.asDouble, z = params.get("z")?.asDouble,
                blockName = params.get("blockName")?.asString)
            "attackNearest" -> {
                val range = params.get("range")?.asInt ?: 5
                val type = params.get("type")?.asString
                cn.qlm.player2.manager.Action("attack")
            }
            else -> null
        }
        if (a != null) ActionExecutor.enqueue(p, listOf(a))
    }

    /** 把官方 FunctionCall（name + arguments JSON）映射为 mod 的 Action */
    private fun functionCallToAction(name: String, args: JsonObject): cn.qlm.player2.manager.Action? {
        return when (name) {
            "move" -> cn.qlm.player2.manager.Action("move", direction = args.get("direction")?.asString, durationMs = args.get("durationMs")?.asLong ?: 300)
            "look" -> cn.qlm.player2.manager.Action("look", yaw = args.get("yaw")?.asFloat, pitch = args.get("pitch")?.asFloat)
            "lookAt" -> cn.qlm.player2.manager.Action("lookAt", x = args.get("x")?.asDouble, y = args.get("y")?.asDouble, z = args.get("z")?.asDouble)
            "breakBlock" -> cn.qlm.player2.manager.Action("break", x = args.get("x")?.asDouble, y = args.get("y")?.asDouble, z = args.get("z")?.asDouble)
            "placeBlock" -> cn.qlm.player2.manager.Action("place", x = args.get("x")?.asDouble, y = args.get("y")?.asDouble, z = args.get("z")?.asDouble, blockName = args.get("blockName")?.asString)
            "attackNearest" -> cn.qlm.player2.manager.Action("attackNearest", direction = args.get("type")?.asString, durationMs = args.get("range")?.asLong ?: 5)
            "attackEntity" -> cn.qlm.player2.manager.Action("attack", targetEntityId = args.get("entityId")?.asInt)
            "jump" -> cn.qlm.player2.manager.Action("jump")
            "stop" -> cn.qlm.player2.manager.Action("stop")
            "switchSlot" -> cn.qlm.player2.manager.Action("switchSlot", slot = args.get("slot")?.asInt)
            "useItem" -> cn.qlm.player2.manager.Action("useItem")
            "chat" -> cn.qlm.player2.manager.Action("chat", message = args.get("message")?.asString)
            else -> null
        }
    }
}
