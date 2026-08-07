const vec3 = require('vec3');

class ActionExecutor {
  constructor(bot) {
    this.bot = bot;
    this._moveTimers = {};
    this._busy = false;
  }

  async execute(actions) {
    if (!Array.isArray(actions)) return;
    for (const action of actions) {
      try { await this._runOne(action); }
      catch (err) { console.error('[Action Error]', action.type, err.message); }
    }
  }

  async _runOne(a) {
    switch (a.type) {
      case 'move':       return this.move(a.direction, a.durationMs || 300);
      case 'look':       return this.look(a.yaw, a.pitch);
      case 'lookAt':     return this.lookAt(a.x, a.y, a.z);
      case 'break':      return this.breakBlock(a.targetBlock?.x, a.targetBlock?.y, a.targetBlock?.z);
      case 'place':      return this.placeBlock(a.x, a.y, a.z, a.blockId);
      case 'attack':     return this.attackEntity(a.targetEntityId);
      case 'interact':   return this.interactBlock(a.targetBlock?.x, a.targetBlock?.y, a.targetBlock?.z);
      case 'useItem':    return this.useItem(a.slot);
      case 'switchSlot': return this.switchSlot(a.slot);
      case 'jump':       return this.jump(a.times || 1);
      case 'sprint':     return this.setSprint(!!a.enable);
      case 'sneak':      return this.setSneak(!!a.enable);
      case 'stop':       return this.stopAll();
      case 'chat':       return this.chat(a.message);
      default: console.warn('[Action] Unknown type:', a.type);
    }
  }

  move(direction, durationMs = 300) {
    const bot = this.bot;
    const key = {
      forward: 'forward', back: 'back', left: 'left', right: 'right',
      up: 'jump', down: 'sneak'
    }[direction];
    if (!key) return;

    if (this._moveTimers[key]) {
      clearTimeout(this._moveTimers[key]);
    }
    bot.setControlState(key, true);
    this._moveTimers[key] = setTimeout(() => {
      bot.setControlState(key, false);
      delete this._moveTimers[key];
    }, durationMs);
  }

  look(yaw, pitch) {
    return this.bot.look(yaw, pitch, true);
  }

  lookAt(x, y, z) {
    if (x == null) return;
    return this.bot.lookAt(vec3(x, y, z));
  }

  async breakBlock(x, y, z) {
    if (x == null) return;
    const pos = vec3(x, y, z);
    const block = this.bot.blockAt(pos);
    if (!block || block.name === 'air') return;
    await this.bot.dig(block);
  }

  async placeBlock(x, y, z, blockName) {
    if (x == null) return;
    const bot = this.bot;
    if (blockName) {
      const item = bot.inventory.items().find(it => it.name === blockName);
      if (item) await bot.equip(item, 'hand');
    }
    const targetPos = vec3(x, y, z);
    const ref = bot.blockAt(targetPos.offset(0, -1, 0));
    if (!ref) return;
    try { await bot.placeBlock(ref, new vec3(0, 1, 0)); }
    catch (e) { /* ignore */ }
  }

  attackEntity(entityId) {
    const entity = this.bot.entities[entityId];
    if (!entity) return;
    this.bot.attack(entity);
  }

  attackNearest(type = 'mob', range = 5) {
    const self = this.bot.entity.position;
    let nearest = null, nearestDist = Infinity;
    for (const e of Object.values(this.bot.entities)) {
      if (!e || e === this.bot.entity) continue;
      if (type === 'mob' && e.type !== 'mob' && e.type !== 'hostile') continue;
      if (type === 'player' && e.type !== 'player') continue;
      const d = e.position.distanceTo(self);
      if (d < range && d < nearestDist) { nearestDist = d; nearest = e; }
    }
    if (nearest) this.bot.attack(nearest);
  }

  async interactBlock(x, y, z) {
    if (x == null) return;
    const block = this.bot.blockAt(vec3(x, y, z));
    if (block) await this.bot.activateBlock(block);
  }

  useItem(slot) {
    return this.bot.activateItem();
  }

  async switchSlot(slot) {
    if (slot == null) return;
    await this.bot.setQuickBarSlot(Math.max(0, Math.min(8, slot)));
  }

  jump(times = 1) {
    return new Promise((resolve) => {
      let n = 0;
      const iv = setInterval(() => {
        this.bot.setControlState('jump', true);
        setTimeout(() => this.bot.setControlState('jump', false), 100);
        n++;
        if (n >= times) { clearInterval(iv); resolve(); }
      }, 250);
    });
  }

  setSprint(v) { this.bot.setControlState('sprint', v); }
  setSneak(v)  { this.bot.setControlState('sneak', v); }

  stopAll() {
    for (const k of ['forward', 'back', 'left', 'right', 'jump', 'sprint', 'sneak']) {
      this.bot.setControlState(k, false);
    }
    for (const k of Object.keys(this._moveTimers)) {
      clearTimeout(this._moveTimers[k]);
    }
    this._moveTimers = {};
    this.bot.deactivateItem();
  }

  chat(message) {
    if (message) this.bot.chat(message);
  }

  /**
   * 执行官方 FunctionCall（来自 /npcs/responses 的 command 项）
   * fc = { name: string, arguments: string(JSON) }
   * name 对齐 npcManager.DEFAULT_MC_COMMANDS 的工具名。
   */
  async executeFunctionCall(fc) {
    if (!fc || !fc.name) return;
    let args = {};
    try { args = JSON.parse(fc.arguments || '{}'); } catch (e) { /* 空参数 */ }
    switch (fc.name) {
      case 'move':           return this.move(args.direction, args.durationMs);
      case 'look':           return this.look(args.yaw, args.pitch);
      case 'lookAt':         return this.lookAt(args.x, args.y, args.z);
      case 'breakBlock':     return this.breakBlock(args.x, args.y, args.z);
      case 'placeBlock':     return this.placeBlock(args.x, args.y, args.z, args.blockName);
      case 'attackNearest':  return this.attackNearest(args.type, args.range);
      case 'attackEntity':   return this.attackEntity(args.entityId);
      case 'jump':           return this.jump();
      case 'stop':           return this.stopAll();
      case 'switchSlot':     return this.switchSlot(args.slot);
      case 'useItem':        return this.useItem();
      case 'chat':           return this.chat(args.message);
      default: console.warn('[FunctionCall] unknown command:', fc.name);
    }
  }
}

module.exports = ActionExecutor;
