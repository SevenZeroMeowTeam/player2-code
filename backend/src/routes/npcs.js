const express = require('express');
const auth = require('../middleware/auth');

/**
 * 创建对齐 player2-sdk-ts 官方 API 契约的路由。
 * 依赖注入：{ npcManager, aiOrchestrator, clientRegistry, io }
 * 端点：
 *   POST /npcs/spawn            创建 NPC（= 假玩家）
 *   GET  /npcs/responses        实时响应流（SSE 或 newline JSON）
 *   POST /npcs/:npcId/chat      向 NPC 发消息
 *   POST /npcs/:npcId/kill      删除 NPC
 *   GET  /npcs/:npcId/history   对话历史
 *   GET  /joules                余额（自托管返回无限）
 *   GET  /selected_characters   角色（返回空）
 *   GET  /tts/voices            TTS 语音列表（返回空）
 */
function createNpcRouter({ npcManager, aiOrchestrator, clientRegistry, io }) {
  const router = express.Router();

  // 鉴权：仅作用于官方端点路径，支持 Authorization 头 与 ?token= 查询参数（EventSource 无法设 header）
  const PROTECTED_PREFIXES = ['/npcs', '/joules', '/selected_characters', '/tts'];
  router.use((req, res, next) => {
    const path = req.path;
    if (!PROTECTED_PREFIXES.some(p => path === p || path.startsWith(p + '/') || path === p)) {
      return next(); // 非官方端点（如 /health, /api/v1/auth/login），放行
    }
    if (req.query.token && !req.headers.authorization) {
      req.headers.authorization = 'Bearer ' + req.query.token;
    }
    return auth.verify(req, res, next);
  });

  // POST /npcs/spawn
  router.post('/npcs/spawn', (req, res) => {
    const userId = req.user.userId;
    const body = req.body || {};
    if (!body.name) {
      return res.status(400).json({ error: 'name is required' });
    }
    const { npcId, npc } = npcManager.spawn(userId, body);
    npc.bridgePlayerId = body.name;

    // 通知 bridge/mod 创建假玩家
    const bridge = clientRegistry.getBridgeForUser(userId);
    if (bridge) {
      bridge.emit('player:spawn', {
        playerId: npc.bridgePlayerId,
        npcId,
        name: npc.name,
        short_name: npc.short_name,
        character_description: npc.character_description,
        system_prompt: npc.system_prompt
      });
    }

    console.log(`[NPC] spawn npc=${npcId} name=${npc.name} user=${userId}`);
    // 官方返回纯字符串 UUID
    return res.status(200).type('text/plain').send(npcId);
  });

  // GET /npcs/responses —— 实时响应流
  router.get('/npcs/responses', async (req, res) => {
    const userId = req.user.userId;
    const accept = req.headers.accept || '';
    const isSSE = accept.includes('text/event-stream');
    const ttsStreaming = req.query['tts-streaming'] === 'true' || req.query.ttsStreaming === 'true';

    if (isSSE) {
      res.writeHead(200, {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache, no-transform',
        'Connection': 'keep-alive',
        'X-Accel-Buffering': 'no'
      });
      res.write(': connected\n\n');
      res.flushHeaders?.();

      const pingTimer = setInterval(() => {
        res.write('event: ping\ndata: {"type":"ping"}\n\n');
      }, 15000);

      req.on('close', () => {
        clearInterval(pingTimer);
      });

      // 持续推送直到客户端断开
      while (!req.destroyed && !res.writableEnded) {
        const resp = await npcManager.waitForResponse(userId, 20000);
        if (resp) {
          res.write(`event: npc_response\ndata: ${JSON.stringify(resp)}\n\n`);
        } else if (!req.destroyed) {
          res.write(': keepalive\n\n');
        }
      }
    } else {
      // newline-delimited JSON 流
      res.writeHead(200, {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-cache, no-transform',
        'Connection': 'keep-alive',
        'X-Accel-Buffering': 'no'
      });
      res.flushHeaders?.();

      const keepTimer = setInterval(() => {
        if (!req.destroyed) res.write('\n');
      }, 15000);

      req.on('close', () => clearInterval(keepTimer));

      while (!req.destroyed && !res.writableEnded) {
        const resp = await npcManager.waitForResponse(userId, 20000);
        if (resp) {
          res.write(JSON.stringify(resp) + '\n');
        }
      }
    }
  });

  // POST /npcs/:npcId/chat
  router.post('/npcs/:npcId/chat', (req, res) => {
    const userId = req.user.userId;
    const npcId = req.params.npcId;
    if (!npcManager.owns(userId, npcId)) {
      return res.status(404).json({ error: 'NPC not found' });
    }
    const npc = npcManager.get(npcId);
    const body = req.body || {};
    if (!body.sender_message || !body.sender_name) {
      return res.status(400).json({ error: 'sender_message and sender_name are required' });
    }

    npcManager.pushUserMessage(npcId, {
      sender_name: body.sender_name,
      sender_message: body.sender_message,
      game_state_info: body.game_state_info
    });

    // 异步处理：调 LLM → 入历史 → 入响应队列 → 转发 bridge/mod
    (async () => {
      const result = await aiOrchestrator.npcChat(
        npc, body.sender_name, body.sender_message, body.game_state_info
      );
      npcManager.pushAssistantMessage(npcId, result.message, result._toolCallsForHistory);

      const resp = {
        npc_id: npcId,
        message: result.message,
        command: result.command,
        audio: null,
        error: result.error
      };
      npcManager.enqueueResponse(userId, resp);

      // 转发给 bridge/mod 执行动作 + 说话
      const bridge = clientRegistry.getBridgeForUser(userId);
      if (bridge) {
        bridge.emit('npc:response', {
          playerId: npc.bridgePlayerId || npc.name,
          npcId,
          message: result.message,
          command: result.command,
          reasoning: result._reasoning
        });
      }
      // 通知 web 客户端（实时刷新）
      const web = clientRegistry.getWebForUser(userId);
      if (web) {
        web.emit('npc:response', {
          npcId,
          message: result.message,
          command: result.command,
          reasoning: result._reasoning,
          error: result.error
        });
      }
    })().catch(err => console.error('[npcChat async]', err));

    return res.status(200).json({ queued: true, npc_id: npcId });
  });

  // POST /npcs/:npcId/kill
  router.post('/npcs/:npcId/kill', (req, res) => {
    const userId = req.user.userId;
    const npcId = req.params.npcId;
    const npc = npcManager.get(npcId);
    if (!npcManager.owns(userId, npcId)) {
      return res.status(404).json({ error: 'NPC not found' });
    }
    npcManager.kill(npcId);

    // 通知 bridge/mod 移除假玩家
    const bridge = clientRegistry.getBridgeForUser(userId);
    if (bridge) {
      bridge.emit('player:kill', { playerId: npc.bridgePlayerId || npc.name, npcId });
    }
    console.log(`[NPC] kill npc=${npcId}`);
    return res.status(200).json({ killed: true, npc_id: npcId });
  });

  // GET /npcs/:npcId/history
  router.get('/npcs/:npcId/history', (req, res) => {
    const userId = req.user.userId;
    const npcId = req.params.npcId;
    if (!npcManager.owns(userId, npcId)) {
      return res.status(404).json({ error: 'NPC not found' });
    }
    const history = npcManager.getHistory(npcId);
    return res.status(200).json({ npc_id: npcId, history });
  });

  // GET /joules —— 自托管返回无限余额
  router.get('/joules', (req, res) => {
    res.status(200).json({ joules: 999999, patron_tier: 'Patron VVIP' });
  });

  // GET /selected_characters —— 暂未接入角色库
  router.get('/selected_characters', (req, res) => {
    res.status(200).json({ characters: [] });
  });

  // GET /tts/voices —— TTS 暂未启用
  router.get('/tts/voices', (req, res) => {
    res.status(200).json({ voices: [] });
  });

  // 列出当前用户的 NPC（扩展端点，便于管理面板）
  router.get('/npcs', (req, res) => {
    const list = npcManager.listByUser(req.user.userId).map(n => ({
      npc_id: n.id,
      name: n.name,
      short_name: n.short_name,
      character_description: n.character_description,
      bridgePlayerId: n.bridgePlayerId,
      createdAt: n.createdAt
    }));
    res.status(200).json({ npcs: list });
  });

  return router;
}

module.exports = createNpcRouter;
