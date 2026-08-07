const axios = require('axios');
const { v4: uuidv4 } = require('uuid');

class AIOrchestrator {
  constructor(apiBase, apiKey, modelName) {
    this.apiBase = apiBase.replace(/\/$/, '');
    this.apiKey = apiKey;
    this.model = modelName || process.env.AI_MODEL || 'deepseek-reasoner';
    this.players = new Map();
    this.promptTemplates = {
      system: `你是一个 Minecraft AI 玩家助手。
【严格输出要求】：最后只输出一个合法的 JSON 对象，不要包含任何 markdown 标记、代码块或额外说明文字。
JSON 格式:
{
  "reasoning": "简短推理，不超过 100 字，解释为什么做这些动作",
  "actions": [
    {"type":"move","direction":"forward|back|left|right|up|down","durationMs":300},
    {"type":"look","yaw":0.0,"pitch":0.0},
    {"type":"lookAt","x":0.0,"y":0.0,"z":0.0},
    {"type":"break","targetBlock":{"x":0,"y":0,"z":0}},
    {"type":"place","blockId":"stone","x":0,"y":0,"z":0},
    {"type":"attack","targetEntityId":1234},
    {"type":"interact","targetBlock":{"x":0,"y":0,"z":0}},
    {"type":"useItem","slot":0},
    {"type":"switchSlot","slot":1},
    {"type":"jump"},
    {"type":"sprint","enable":true},
    {"type":"sneak","enable":false},
    {"type":"stop"},
    {"type":"chat","message":"你好"}
  ]
}
每次最多输出 5 个动作。只在必要时进行战斗，饥饿值低于 15 时优先吃东西。`,
      chat: `你是一名真实的 Minecraft 玩家，名字叫 {name}，性格：{personality}。
根据对方说的话用 Minecraft 玩家的口吻回复，简短自然，口语化，不要超过 60 字。
禁止输出任何 AI 助手的语气，禁止透露你是 AI。`
    };
  }

  get chatModel() {
    return process.env.AI_CHAT_MODEL || this.model;
  }

  /**
   * 官方 NPC 对话模式（对齐 POST /npcs/{id}/chat + /npcs/responses）
   * 用 NPC 的 system_prompt + character_description 构建系统消息，
   * 把 NPC 的 commands 转成 OpenAI tools，由 LLM 决定回复文本与函数调用(command)。
   * 返回 NpcApiChatResponse 结构：{ npc_id, message, command, audio, error, _reasoning }
   */
  async npcChat(npc, senderName, senderMessage, gameStateInfo) {
    const systemParts = [npc.system_prompt];
    if (npc.character_description) systemParts.push(`\n[角色背景] ${npc.character_description}`);
    systemParts.push(`\n你的名字是 ${npc.name}。你身处真实的 Minecraft 1.20.1 生存世界，可以借助提供的函数移动/挖掘/战斗/聊天。回复要简短自然，像真实玩家。`);
    const system = systemParts.join('');

    const userContent = gameStateInfo
      ? `[当前游戏状态]\n${gameStateInfo}\n\n${senderName}: ${senderMessage}`
      : `${senderName}: ${senderMessage}`;

    const messages = [
      { role: 'system', content: system },
      ...(npc.history || []),
      { role: 'user', content: userContent }
    ];

    const model = this.chatModel;
    const isReasoner = /reasoner|r1/i.test(model);
    const tools = (npc.commands || []).map(c => ({
      type: 'function',
      function: { name: c.name, description: c.description, parameters: c.parameters }
    }));

    const payload = { model, messages, temperature: isReasoner ? 0.95 : 0.8 };
    if (!isReasoner && tools.length) {
      payload.tools = tools;
      payload.tool_choice = 'auto';
    }

    try {
      const resp = await axios.post(
        `${this.apiBase}/chat/completions`,
        payload,
        {
          headers: { 'Authorization': `Bearer ${this.apiKey}`, 'Content-Type': 'application/json' },
          timeout: 60000
        }
      );
      const msg = resp.data.choices[0].message;
      const reasoning = msg.reasoning_content || msg.thinking_content || '';

      let command = null;
      let toolCallsForHistory = null;

      if (msg.tool_calls && msg.tool_calls.length) {
        toolCallsForHistory = msg.tool_calls;
        command = msg.tool_calls.map(tc => ({
          name: tc.function.name,
          arguments: tc.function.arguments
        }));
      } else if (isReasoner) {
        // R1 不支持 tool_calls，尝试从 content 解析 JSON 动作
        const parsed = this._safeParse(msg.content || '');
        if (parsed && Array.isArray(parsed.actions) && parsed.actions.length) {
          command = parsed.actions.map(a => ({
            name: a.type,
            arguments: JSON.stringify(a)
          }));
        }
      }

      let message = (msg.content || '').trim();
      // 若所有 command 都是 silent（never_respond_with_message），则清空文本
      if (command && command.length) {
        const silentNames = new Set(
          (npc.commands || []).filter(c => c.never_respond_with_message).map(c => c.name)
        );
        if (silentNames.size && command.every(c => silentNames.has(c.name))) {
          message = '';
        }
      }

      return {
        npc_id: npc.id,
        message,
        command,
        audio: null,
        error: null,
        _reasoning: reasoning,
        _toolCallsForHistory: toolCallsForHistory
      };
    } catch (err) {
      console.error('[NPC Chat failed]', err.response?.data || err.message);
      return {
        npc_id: npc.id,
        message: '',
        command: null,
        audio: null,
        error: {
          error_code: err.response?.status === 429 ? 'rate_limited'
            : err.response?.status === 402 ? 'insufficient_credits'
            : 'service_unavailable',
          error_message: err.message || 'AI 服务不可达'
        }
      };
    }
  }

  async createPlayer(config) {
    const player = {
      ...config,
      id: config.playerId || uuidv4(),
      memory: [],
      createdAt: Date.now()
    };
    this.players.set(player.id, player);
    return player;
  }

  getPlayer(playerId) {
    return this.players.get(playerId);
  }

  _buildPerceptionPrompt(player, perception) {
    const p = JSON.stringify(perception, null, 0);
    const recentMemory = player.memory.slice(-5).map(m => `- ${m.ts}: ${m.summary}`).join('\n');
    return `玩家名: ${player.name}
模式: ${player.mode || 'survival'}
性格: ${player.personality || 'normal'}
位置: x=${perception.self?.x?.toFixed(1)} y=${perception.self?.y?.toFixed(1)} z=${perception.self?.z?.toFixed(1)}
生命值: ${perception.self?.health ?? 20}/20
饥饿值: ${perception.self?.food ?? 20}/20
背包: ${JSON.stringify(perception.inventory?.slice?.(0, 9) || [])}

周围实体 (20格内):
${(perception.entities || []).slice(0, 15).map(e => `  [${e.type}] ${e.name} id=${e.id} x=${e.x.toFixed(1)} y=${e.y.toFixed(1)} z=${e.z.toFixed(1)} h=${e.health ?? '?'}`).join('\n') || '  (无)'}

周围方块 (视线与附近):
${(perception.nearbyBlocks || []).slice(0, 20).map(b => `  ${b.name} @(${b.x},${b.y},${b.z})`).join('\n') || '  (无)'}

视线目标: ${perception.lookingAt ? `${perception.lookingAt.name} @(${perception.lookingAt.x},${perception.lookingAt.y},${perception.lookingAt.z})` : '空气'}

原始感知: ${p.length > 800 ? p.slice(0, 800) + '...' : p}

近期记忆:
${recentMemory || '  (无)'}

请输出决策 JSON。`;
  }

  async processPerception(playerId, perception) {
    const player = this.players.get(playerId);
    if (!player) throw new Error(`Player ${playerId} not found`);

    const userPrompt = this._buildPerceptionPrompt(player, perception);
    const isReasoner = this.model.toLowerCase().includes('reasoner') || this.model.toLowerCase().includes('r1');

    try {
      const payload = {
        model: this.model,
        temperature: isReasoner ? 0.95 : 0.7,
        messages: [
          { role: 'system', content: this.promptTemplates.system },
          { role: 'user', content: userPrompt }
        ]
      };
      if (!isReasoner) payload.response_format = { type: 'json_object' };

      const resp = await axios.post(
        `${this.apiBase}/chat/completions`,
        payload,
        {
          headers: {
            'Authorization': `Bearer ${this.apiKey}`,
            'Content-Type': 'application/json'
          },
          timeout: 60000
        }
      );

      const choice = resp.data.choices[0];
      const raw = choice.message.content || '';
      const thinking = choice.message.reasoning_content || choice.message.thinking_content || '';
      const parsed = this._safeParse(raw);

      const reasoning = (parsed?.reasoning) || thinking.slice(0, 200) || '(无)';
      if (parsed?.reasoning) {
        player.memory.push({ ts: Date.now(), summary: parsed.reasoning });
      } else if (thinking) {
        player.memory.push({ ts: Date.now(), summary: thinking.slice(0, 80) });
      }
      return parsed;
    } catch (err) {
      console.error('[AI Call failed]', err.response?.data || err.message);
      return this._fallbackDecision(perception);
    }
  }

  async chat(playerId, sender, message) {
    const player = this.players.get(playerId);
    if (!player) return null;
    const system = this.promptTemplates.chat
      .replace('{name}', player.name)
      .replace('{personality}', player.personality || '友好开朗');
    try {
      const resp = await axios.post(
        `${this.apiBase}/chat/completions`,
        {
          model: process.env.AI_CHAT_MODEL || this.model,
          temperature: 0.9,
          messages: [
            { role: 'system', content: system },
            { role: 'user', content: `${sender}: ${message}` }
          ]
        },
        {
          headers: { 'Authorization': `Bearer ${this.apiKey}`, 'Content-Type': 'application/json' },
          timeout: 30000
        }
      );
      return (resp.data.choices[0].message.content || '嗯...').trim().slice(0, 120);
    } catch (err) {
      console.error('[Chat Error]', err.response?.data || err.message);
      return '哈哈好~';
    }
  }

  _safeParse(text) {
    try {
      let s = text.trim();
      const m1 = s.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
      if (m1) s = m1[1];
      const idx = s.indexOf('{');
      const endIdx = s.lastIndexOf('}');
      if (idx >= 0 && endIdx > idx) s = s.slice(idx, endIdx + 1);
      const obj = JSON.parse(s);
      if (!Array.isArray(obj.actions)) obj.actions = [];
      return obj;
    } catch (e) {
      console.warn('[JSON parse fail] head:', text.slice(0, 200));
      return null;
    }
  }

  _fallbackDecision(perception) {
    return {
      reasoning: 'AI 服务不可达，使用回退策略：原地不动',
      actions: []
    };
  }
}

module.exports = AIOrchestrator;
