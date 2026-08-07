package cn.qlm.player2.manager

import cn.qlm.player2.Player2Mod
import net.minecraft.core.BlockPos
import net.minecraft.core.Direction
import net.minecraft.world.InteractionHand
import net.minecraft.world.entity.player.Player
import net.minecraft.world.level.Level
import net.minecraft.world.level.block.state.BlockState
import net.minecraft.world.phys.BlockHitResult
import net.minecraft.world.phys.Vec3
import net.minecraftforge.common.ForgeMod
import net.minecraftforge.event.TickEvent
import net.minecraftforge.eventbus.api.SubscribeEvent
import net.minecraftforge.fml.common.Mod
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.math.atan2
import kotlin.math.sqrt

data class Action(
    val type: String,
    val direction: String? = null,
    val durationMs: Long = 300,
    val yaw: Float? = null,
    val pitch: Float? = null,
    val x: Double? = null, val y: Double? = null, val z: Double? = null,
    val targetEntityId: Int? = null,
    val slot: Int? = null,
    val message: String? = null,
    val blockName: String? = null
)

@Mod.EventBusSubscriber(modid = Player2Mod.MOD_ID)
object ActionExecutor {

    private val queue = ConcurrentLinkedQueue<Pair<Player, Action>>()
    private val activeMoves = mutableMapOf<String, Long>() // key = name:dir -> endAt ms

    fun enqueue(player: Player, actions: List<Action>) {
        actions.forEach { queue.offer(player to it) }
    }

    @SubscribeEvent
    fun onTick(event: TickEvent.ServerTickEvent) {
        if (event.phase != TickEvent.Phase.END) return

        val now = System.currentTimeMillis()
        val iter = activeMoves.entries.iterator()
        while (iter.hasNext()) {
            val e = iter.next()
            if (now >= e.value) {
                val (name, dir) = e.key.split(":", limit = 2)
                iter.remove()
            }
        }

        repeat(20) {
            val (player, action) = queue.poll() ?: return@repeat
            try { executeOne(player, action) }
            catch (t: Throwable) { Player2Mod.LOG.error("[Action Error]", t) }
        }
    }

    private fun executeOne(p: Player, a: Action) {
        val level = p.level() as? net.minecraft.server.level.ServerLevel ?: return
        when (a.type) {
            "move" -> setMove(p, a.direction, a.durationMs)
            "look" -> look(p, a.yaw, a.pitch)
            "lookAt" -> lookAt(p, a.x, a.y, a.z)
            "break" -> breakBlock(p, a.x, a.y, a.z)
            "place" -> placeBlock(p, a.x, a.y, a.z, a.blockName)
            "attack" -> attackEntity(p, a.targetEntityId)
            "attackNearest" -> attackNearest(p, a.direction, a.durationMs.toInt())
            "interact" -> interactBlock(p, a.x, a.y, a.z)
            "useItem" -> useItem(p)
            "switchSlot" -> switchSlot(p, a.slot)
            "jump" -> jump(p)
            "sprint" -> p.isSprinting = (a.direction == "true")
            "sneak" -> p.setShiftKeyDown(a.direction == "true")
            "stop" -> stopAll(p)
            "chat" -> chat(p, a.message)
            else -> Player2Mod.LOG.warn("Unknown action type: ${a.type}")
        }
    }

    private fun setMove(p: Player, dir: String?, durationMs: Long) {
        when (dir) {
            "forward" -> { p.zza = 1.0f; scheduleClear(p, "forward", durationMs) { it.zza = 0f } }
            "back" -> { p.zza = -1.0f; scheduleClear(p, "back", durationMs) { it.zza = 0f } }
            "left" -> { p.xxa = -1.0f; scheduleClear(p, "left", durationMs) { it.xxa = 0f } }
            "right" -> { p.xxa = 1.0f; scheduleClear(p, "right", durationMs) { it.xxa = 0f } }
            "up" -> jump(p)
            "down" -> p.setShiftKeyDown(true).also { scheduleClear(p, "down", durationMs) { it.setShiftKeyDown(false) } }
        }
    }

    private fun scheduleClear(p: Player, key: String, durationMs: Long, clear: (Player) -> Unit) {
        val endAt = System.currentTimeMillis() + durationMs
        activeMoves["${p.gameProfile.name}:$key"] = endAt
        Thread {
            Thread.sleep(durationMs + 50)
            if (p.isAlive) clear(p)
        }.apply { isDaemon = true }.start()
    }

    private fun look(p: Player, yaw: Float?, pitch: Float?) {
        if (yaw != null) p.yRot = yaw
        if (pitch != null) p.xRot = pitch
    }

    private fun lookAt(p: Player, x: Double?, y: Double?, z: Double?) {
        if (x == null || y == null || z == null) return
        val dx = x - p.x; val dy = y - (p.y + p.eyeHeight); val dz = z - p.z
        val dist = sqrt(dx*dx + dz*dz)
        val pitch = -Math.toDegrees(atan2(dy, dist)).toFloat()
        val yaw = (Math.toDegrees(atan2(dz, dx)) - 90).toFloat()
        look(p, yaw, pitch)
    }

    private fun breakBlock(p: Player, x: Double?, y: Double?, z: Double?) {
        if (x == null || y == null || z == null) return
        val pos = BlockPos(x.toInt(), y.toInt(), z.toInt())
        val sp = p as? net.minecraft.server.level.ServerPlayer ?: return
        lookAt(p, x + 0.5, y + 0.5, z + 0.5)
        sp.gameMode.destroyBlock(pos)
    }

    private fun placeBlock(p: Player, x: Double?, y: Double?, z: Double?, blockName: String?) {
        if (x == null || y == null || z == null) return
        val sp = p as? net.minecraft.server.level.ServerPlayer ?: return
        val level = sp.serverLevel()
        val placePos = BlockPos(x.toInt(), y.toInt(), z.toInt())
        lookAt(p, x + 0.5, y + 0.5, z + 0.5)
        val hit = BlockHitResult(Vec3(x + 0.5, y.toDouble(), z + 0.5), Direction.UP, placePos.below(), false)
        sp.gameMode.useItemOn(sp, level, sp.mainHandItem, InteractionHand.MAIN_HAND, hit)
    }

    private fun attackEntity(p: Player, targetId: Int?) {
        if (targetId == null) return
        val sp = p as? net.minecraft.server.level.ServerPlayer ?: return
        val target = sp.level().getEntity(targetId) ?: return
        sp.attack(target)
    }

    private fun attackNearest(p: Player, type: String?, range: Int) {
        val sp = p as? net.minecraft.server.level.ServerPlayer ?: return
        val level = sp.serverLevel()
        val r = if (range > 0) range else 5
        val target = level.allEntities.asIterable().filter { e ->
            e !== p && e.isAlive && e.distanceTo(p) <= r && when (type) {
                "mob" -> e is net.minecraft.world.entity.Mob
                "player" -> e is Player && e !== p
                else -> true
            }
        }.minByOrNull { it.distanceTo(p) }
        if (target != null) sp.attack(target)
    }

    private fun interactBlock(p: Player, x: Double?, y: Double?, z: Double?) {
        if (x == null || y == null || z == null) return
        val sp = p as? net.minecraft.server.level.ServerPlayer ?: return
        val pos = BlockPos(x.toInt(), y.toInt(), z.toInt())
        lookAt(p, x + 0.5, y + 0.5, z + 0.5)
        val hit = BlockHitResult(Vec3(x + 0.5, y + 0.5, z + 0.5), Direction.NORTH, pos, false)
        sp.gameMode.useItemOn(sp, sp.serverLevel(), sp.mainHandItem, InteractionHand.MAIN_HAND, hit)
    }

    private fun useItem(p: Player) {
        val sp = p as? net.minecraft.server.level.ServerPlayer ?: return
        sp.gameMode.useItem(sp, sp.serverLevel(), sp.mainHandItem, InteractionHand.MAIN_HAND)
    }

    private fun switchSlot(p: Player, slot: Int?) {
        if (slot == null) return
        p.inventory.selected = (slot and 0xFFFF).coerceIn(0, 8)
    }

    private fun jump(p: Player) {
        if (p.onGround()) p.jumpFromGround()
    }

    private fun stopAll(p: Player) {
        p.xxa = 0f; p.zza = 0f
        p.setShiftKeyDown(false)
        p.isSprinting = false
    }

    private fun chat(p: Player, message: String?) {
        if (message == null) return
        val sp = p as? net.minecraft.server.level.ServerPlayer ?: return
        val component = net.minecraft.network.chat.Component.literal("<${p.gameProfile.name}> $message")
        sp.sendSystemMessage(component)
    }
}
