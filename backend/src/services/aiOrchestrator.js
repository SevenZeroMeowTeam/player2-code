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
