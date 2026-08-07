const { v4: uuidv4 } = require('uuid');

/**
 * 默认 Minecraft 动作 commands（对齐官方 Function 工具定义）
 * NPC 若未自定义 commands，则使用这套工具，LLM 通过 tool_calls 驱动假玩家行动。
 * 字段结构与 player2-sdk-ts 的 Function 类型一致：
 *   { name, description, parameters: {type, properties, required}, never_respond_with_message? }
 */
const DEFAULT_MC_COMMANDS = [
  {
    name: 'move',
    description: '让假玩家朝指定方向移动一段时间。direction 可选 forward/back/left/right/up(跳)/down(潜行)。',
    parameters: {
      type: 'object',
      properties: {
        direction: { type: 'string', enum: ['forward', 'back', 'left', 'right', 'up', 'down'] },
        durationMs: { type: 'number', description: '持续毫秒数，默认 300' }
      },
      required: ['direction']
    }
  },
  {
    name: 'lookAt',
    description: '让假玩家看向指定坐标。',
    parameters: {
      type: 'object',
      properties: {
        x: { type: 'number' }, y: { type: 'number' }, z: { type: 'number' }
      },
      required: ['x', 'y', 'z']
    }
  },
  {
    name: 'look',
    description: '按 yaw/pitch 角度调整假玩家视角。',
    parameters: {
      type: 'object',
      properties: { yaw: { type: 'number' }, pitch: { type: 'number' } },
      required: ['yaw', 'pitch']
    }
  },
  {
    name: 'breakBlock',
    description: '破坏指定坐标的方块。',
    parameters: {
      type: 'object',
      properties: { x: { type: 'number' }, y: { type: 'number' }, z: { type: 'number' } },
      required: ['x', 'y', 'z']
    }
  },
  {
    name: 'placeBlock',
    description: '在指定坐标放置方块（优先手持/背包中匹配 blockName 的物品）。',
    parameters: {
      type: 'object',
      properties: {
        x: { type: 'number' }, y: { type: 'number' }, z: { type: 'number' },
        blockName: { type: 'string', description: '方块物品名，如 stone, dirt' }
      },
      required: ['x', 'y', 'z']
    }
  },
  {
    name: 'attackNearest',
    description: '攻击附近最近的实体。',
    parameters: {
      type: 'object',
      properties: {
        type: { type: 'string', enum: ['mob', 'player', 'any'], description: '目标类型' },
        range: { type: 'number', description: '搜索半径，默认 5' }
      }
    }
  },
  {
    name: 'attackEntity',
    description: '按实体 ID 攻击指定实体。',
    parameters: {
      type: 'object',
      properties: { entityId: { type: 'number' } },
      required: ['entityId']
    }
  },
  {
    name: 'jump',
    description: '让假玩家跳跃一次。',
    parameters: { type: 'object', properties: {} }
  },
  {
    name: 'stop',
    description: '停止所有移动/潜行/冲刺状态。',
    parameters: { type: 'object', properties: {} }
  },
  {
    name: 'switchSlot',
    description: '切换快捷栏槽位（0-8）。',
    parameters: {
      type: 'object',
      properties: { slot: { type: 'integer', minimum: 0, maximum: 8 } },
      required: ['slot']
    }
  },
  {
    name: 'useItem',
    description: '使用主手物品（吃东西/使用工具等）。',
    parameters: { type: 'object', properties: {} }
  },
  {
    name: 'chat',
    description: '让假玩家在游戏内发送一条公共聊天消息。',
    parameters: {
      type: 'object',
      properties: { message: { type: 'string' } },
      required: ['message']
    },
    never_respond_with_message: true
  }
];

/**
 * NPC 管理器：生命周期、对话历史、响应队列（供 /npcs/responses SSE 消费）。
 * 对齐 player2-sdk-ts 官方 API 契约（snake_case 字段）。
 */
class NpcManager {
  constructor() {
    this.npcs = new Map();            // npcId -> npc
    this.userNpcs = new Map();        // userId -> Set<npcId>
    this.responseQueues = new Map();  // userId -> NpcApiChatResponse[]
    this.responseWaiters = new Map(); // userId -> Array<resolve>
  }

  /**
   * 创建 NPC（对齐 POST /npcs/spawn）
   * @param {string} userId
   * @param {object} body SpawnNPC 请求体
   * @returns {{ npcId: string, npc: object }}
   */
  spawn(userId, body) {
    const npcId = uuidv4();
    const commands = Array.isArray(body.commands) && body.commands.length
      ? body.commands
      : DEFAULT_MC_COMMANDS;
    const npc = {
      id: npcId,
      userId,
      name: body.name || 'AI_Player',
      short_name: body.short_name || body.name || 'AI',
      character_description: body.character_description || '',
      system_prompt: body.system_prompt || `你是 ${body.name || '一名 AI 玩家'}，一名真实的 Minecraft 玩家。`,
      commands,
      tts: body.tts || null,
      keep_game_state: body.keep_game_state !== false,
      voice_id: body.voice_id || null,
      history: [],
      bridgePlayerId: null,   // 关联的假玩家名（bridge/mod 端）
      bridgeType: null,       // 'bridge' | 'mod'
      createdAt: Date.now()
    };
    this.npcs.set(npcId, npc);
    if (!this.userNpcs.has(userId)) this.userNpcs.set(userId, new Set());
    this.userNpcs.get(userId).add(npcId);
    return { npcId, npc };
  }

  get(npcId) {
    return this.npcs.get(npcId);
  }

  owns(userId, npcId) {
    const npc = this.npcs.get(npcId);
    return !!npc && npc.userId === userId;
  }

  listByUser(userId) {
    const ids = this.userNpcs.get(userId);
    if (!ids) return [];
    return Array.from(ids).map(id => this.npcs.get(id)).filter(Boolean);
  }

  kill(npcId) {
    const npc = this.npcs.get(npcId);
    if (!npc) return false;
    this.npcs.delete(npcId);
    const set = this.userNpcs.get(npc.userId);
    if (set) set.delete(npcId);
    return true;
  }

  /**
   * 追加 user 消息到历史（对齐 NpcChatCompletionRequest）
   */
  pushUserMessage(npcId, { sender_name, sender_message, game_state_info }) {
    const npc = this.npcs.get(npcId);
    if (!npc) return;
    const content = game_state_info
      ? `[游戏状态] ${game_state_info}\n\n${sender_name}: ${sender_message}`
      : `${sender_name}: ${sender_message}`;
    npc.history.push({ role: 'user', content });
  }

  /**
   * 追加 assistant 回复到历史（含可能的 tool_calls）
   */
  pushAssistantMessage(npcId, content, tool_calls) {
    const npc = this.npcs.get(npcId);
    if (!npc) return;
    const msg = { role: 'assistant', content: content || '' };
    if (tool_calls && tool_calls.length) msg.tool_calls = tool_calls;
    npc.history.push(msg);
  }

  getHistory(npcId) {
    const npc = this.npcs.get(npcId);
    return npc ? npc.history : [];
  }

  /**
   * 把一条 NpcApiChatResponse 推入用户响应队列，并唤醒 SSE 消费者。
   * 响应结构对齐官方：{ npc_id, message, command, audio, error }
   */
  enqueueResponse(userId, resp) {
    if (!this.responseQueues.has(userId)) this.responseQueues.set(userId, []);
    this.responseQueues.get(userId).push(resp);
    const waiters = this.responseWaiters.get(userId);
    if (waiters && waiters.length) {
      const resolve = waiters.shift();
      resolve(resp);
    }
  }

  /**
   * 阻塞等待下一条响应（SSE 长轮询用）。超时返回 null。
   */
  waitForResponse(userId, timeoutMs = 25000) {
    return new Promise((resolve) => {
      const queue = this.responseQueues.get(userId);
      if (queue && queue.length) {
        return resolve(queue.shift());
      }
      if (!this.responseWaiters.has(userId)) this.responseWaiters.set(userId, []);
      const waiters = this.responseWaiters.get(userId);
      const timer = setTimeout(() => {
        const idx = waiters.indexOf(resolver);
        if (idx >= 0) waiters.splice(idx, 1);
        resolve(null);
      }, timeoutMs);
      const resolver = (resp) => {
        clearTimeout(timer);
        resolve(resp);
      };
      waiters.push(resolver);
    });
  }

  count() {
    return this.npcs.size;
  }
}

NpcManager.DEFAULT_MC_COMMANDS = DEFAULT_MC_COMMANDS;

module.exports = NpcManager;
