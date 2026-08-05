package cn.qlm.player2.manager

import cn.qlm.player2.Player2Mod
import net.minecraft.core.BlockPos
import net.minecraft.world.entity.Entity
import net.minecraft.world.entity.LivingEntity
import net.minecraft.world.entity.player.Player
import net.minecraft.world.phys.Vec3

data class PerceptionData(
    val ts: Long = System.currentTimeMillis(),
    val self: SelfInfo? = null,
    val lookingAt: LookingAtInfo? = null,
    val inventory: List<ItemInfo> = emptyList(),
    val entities: List<EntityInfo> = emptyList(),
    val nearbyBlocks: List<BlockInfo> = emptyList(),
    val gameMode: String = "survival"
)

data class SelfInfo(
    val name: String,
    val x: Double, val y: Double, val z: Double,
    val yaw: Float, val pitch: Float,
    val health: Float, val maxHealth: Float,
    val food: Int, val saturation: Float,
    val onGround: Boolean, val isInWater: Boolean,
    val xVel: Double, val yVel: Double, val zVel: Double
)

data class LookingAtInfo(
    val name: String,
    val x: Int, val y: Int, val z: Int,
    val displayName: String = ""
)

data class ItemInfo(
    val name: String, val count: Int, val slot: Int, val displayName: String
)

data class EntityInfo(
    val id: Int, val type: String, val name: String,
    val x: Double, val y: Double, val z: Double,
    val health: Float?, val distance: Double
)

data class BlockInfo(
    val name: String, val x: Int, val y: Int, val z: Int
)

object PerceptionCollector {

    fun collect(player: Player, range: Int = 20): PerceptionData {
        val level = player.level()
        val eye = player.getEyePosition(1.0f)
        val look = player.lookAngle

        val hit = player.pick(6.0, 1.0f, false)
        val lookingAt = if (!hit.type.isAir && hit.blockPosition != null) {
            val bs = level.getBlockState(hit.blockPosition)
            LookingAtInfo(
                name = bs.block.descriptionId,
                x = hit.blockPosition.x, y = hit.blockPosition.y, z = hit.blockPosition.z,
                displayName = bs.block.name.string
            )
        } else null

        val entities = mutableListOf<EntityInfo>()
        for (e in level.getEntitiesOfClass(Entity::class.java, player.boundingBox.inflate(range.toDouble()))) {
            if (e == player) continue
            entities.add(
                EntityInfo(
                    id = e.id,
                    type = e.type.descriptionString,
                    name = e.name.string,
                    x = e.x, y = e.y, z = e.z,
                    health = (e as? LivingEntity)?.health,
                    distance = player.distanceTo(e).toDouble()
                )
            )
        }
        entities.sortBy { it.distance }

        val blocks = mutableListOf<BlockInfo>()
        val r = 3
        for (x in -r..r) for (y in -2..2) for (z in -r..r) {
            val bp = BlockPos(player.blockX + x, player.blockY + y, player.blockZ + z)
            val bs = level.getBlockState(bp)
            if (!bs.isAir) {
                blocks.add(
                    BlockInfo(
                        name = bs.block.descriptionId,
                        x = bp.x, y = bp.y, z = bp.z
                    )
                )
                if (blocks.size >= 60) break
            }
        }

        val inv = (0 until player.inventory.containerSize).mapNotNull { idx ->
            val stack = player.inventory.getItem(idx)
            if (stack.isEmpty) return@mapNotNull null
            ItemInfo(
                name = stack.item.descriptionId,
                count = stack.count,
                slot = idx,
                displayName = stack.displayName.string
            )
        }

        return PerceptionData(
            self = SelfInfo(
                name = player.gameProfile.name,
                x = player.x, y = player.y, z = player.z,
                yaw = player.yRot, pitch = player.xRot,
                health = player.health, maxHealth = player.maxHealth,
                food = player.foodData.foodLevel,
                saturation = player.foodData.saturationLevel,
                onGround = player.onGround(),
                isInWater = player.isInWater,
                xVel = player.deltaMovement.x, yVel = player.deltaMovement.y, zVel = player.deltaMovement.z
            ),
            lookingAt = lookingAt,
            inventory = inv,
            entities = entities.take(30),
            nearbyBlocks = blocks,
            gameMode = (player as? net.minecraft.server.level.ServerPlayer)?.gameMode?.gameModeForPlayer?.name?.lowercase() ?: "survival"
        )
    }
}
