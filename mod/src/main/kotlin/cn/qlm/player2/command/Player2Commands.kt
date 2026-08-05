package cn.qlm.player2.command

import cn.qlm.player2.bridge.WsBridgeClient
import cn.qlm.player2.manager.FakePlayerManager
import com.mojang.brigadier.CommandDispatcher
import com.mojang.brigadier.arguments.IntegerArgumentType
import com.mojang.brigadier.arguments.StringArgumentType
import net.minecraft.commands.CommandSourceStack
import net.minecraft.commands.Commands
import net.minecraft.network.chat.Component

object Player2Commands {

    fun register(dispatcher: CommandDispatcher<CommandSourceStack>) {
        val p2 = Commands.literal("p2").requires { it.hasPermission(2) }

        p2.then(Commands.literal("help").executes { ctx ->
            ctx.source.sendSuccess({ Component.literal("=== Player2 Commands ===") }, false)
            ctx.source.sendSuccess({ Component.literal("/p2 spawn <name>  - 创建AI玩家") }, false)
            ctx.source.sendSuccess({ Component.literal("/p2 remove <name> - 移除AI玩家") }, false)
            ctx.source.sendSuccess({ Component.literal("/p2 list          - 列出所有AI玩家") }, false)
            ctx.source.sendSuccess({ Component.literal("/p2 connect <url> <token> - 连接后端") }, false)
            ctx.source.sendSuccess({ Component.literal("/p2 disconnect    - 断开后端连接") }, false)
            1
        })

        p2.then(Commands.literal("spawn")
            .then(Commands.argument("name", StringArgumentType.word())
                .executes { ctx ->
                    val name = StringArgumentType.getString(ctx, "name")
                    val level = ctx.source.level
                    FakePlayerManager.create(name, level)
                    ctx.source.sendSuccess({ Component.literal("AI玩家已创建: $name") }, true)
                    1
                }))

        p2.then(Commands.literal("remove")
            .then(Commands.argument("name", StringArgumentType.word())
                .executes { ctx ->
                    val name = StringArgumentType.getString(ctx, "name")
                    val ok = FakePlayerManager.remove(name)
                    ctx.source.sendSuccess({ Component.literal(if (ok) "已移除: $name" else "玩家不存在: $name") }, true)
                    1
                }))

        p2.then(Commands.literal("list").executes { ctx ->
            val list = FakePlayerManager.list()
            ctx.source.sendSuccess({ Component.literal("AI 玩家 (${list.size}): ${list.joinToString { it.gameProfile.name }}") }, false)
            1
        })

        p2.then(Commands.literal("connect")
            .then(Commands.argument("url", StringArgumentType.string())
                .then(Commands.argument("token", StringArgumentType.string())
                    .executes { ctx ->
                        val url = StringArgumentType.getString(ctx, "url")
                        val token = StringArgumentType.getString(ctx, "token")
                        WsBridgeClient.connectAsync(url, token)
                        ctx.source.sendSuccess({ Component.literal("正在连接 $url ...") }, true)
                        1
                    })))

        p2.then(Commands.literal("disconnect").executes { ctx ->
            WsBridgeClient.disconnect()
            ctx.source.sendSuccess({ Component.literal("已断开连接") }, true)
            1
        })

        dispatcher.register(p2)
    }
}
