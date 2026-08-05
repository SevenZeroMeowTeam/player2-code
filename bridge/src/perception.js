const vec3 = require('vec3');

class PerceptionCollector {
  constructor(bot, viewDistance = 4) {
    this.bot = bot;
    this.viewDistance = viewDistance;
  }

  collect() {
    const bot = this.bot;
    if (!bot?.entity) return {};

    return {
      ts: Date.now(),
      self: this._selfInfo(),
      lookingAt: this._lookingAt(),
      inventory: this._inventory(),
      equipment: this._equipment(),
      entities: this._nearbyEntities(),
      nearbyBlocks: this._nearbyBlocks(),
      biome: this._biome(),
      weather: bot.isRaining ? 'rain' : 'clear',
      gameMode: bot.game.gameMode,
      time: bot.time.timeOfDay
    };
  }

  _selfInfo() {
    const e = this.bot.entity;
    return {
      x: e.position.x, y: e.position.y, z: e.position.z,
      yaw: e.yaw, pitch: e.pitch,
      velocity: { x: e.velocity.x, y: e.velocity.y, z: e.velocity.z },
      health: this.bot.health ?? 20,
      food: this.bot.food ?? 20,
      saturation: this.bot.foodSaturation ?? 0,
      onGround: e.onGround,
      isInWater: e.isInWater,
      isInLava: e.isInLava,
      isSprinting: e.isSprinting,
      isSneaking: e.isSneaking,
      experience: this.bot.experience
    };
  }

  _lookingAt() {
    const r = this.bot.blockAtCursor(6);
    if (!r) return null;
    return {
      name: r.name, type: r.type,
      x: r.position.x, y: r.position.y, z: r.position.z,
      blockId: r.type
    };
  }

  _inventory() {
    return (this.bot.inventory.items() || []).map(it => ({
      name: it.name,
      type: it.type,
      count: it.count,
      slot: it.slot,
      displayName: it.displayName
    }));
  }

  _equipment() {
    const eq = this.bot.equipment;
    return eq.filter(Boolean).map(it => ({
      name: it.name, type: it.type, displayName: it.displayName
    }));
  }

  _nearbyEntities() {
    const self = this.bot.entity;
    const result = [];
    const range = 20;
    for (const [id, e] of Object.entries(this.bot.entities)) {
      if (!e || e === self) continue;
      const dx = e.position.x - self.position.x;
      const dy = e.position.y - self.position.y;
      const dz = e.position.z - self.position.z;
      const dist2 = dx*dx + dy*dy + dz*dz;
      if (dist2 > range * range) continue;
      result.push({
        id: parseInt(id),
        type: e.type || 'unknown',
        name: e.name || e.username || e.displayName || '',
        username: e.username || '',
        x: e.position.x, y: e.position.y, z: e.position.z,
        health: e.health,
        distance: Math.sqrt(dist2),
        velocity: { x: e.velocity?.x, y: e.velocity?.y, z: e.velocity?.z }
      });
    }
    return result.sort((a, b) => a.distance - b.distance);
  }

  _nearbyBlocks() {
    const pos = this.bot.entity.position;
    const blocks = [];
    const R = this.viewDistance;
    for (let x = -R; x <= R; x++) {
      for (let y = -Math.floor(R/2); y <= Math.floor(R/2); y++) {
        for (let z = -R; z <= R; z++) {
          if (x === 0 && y === 0 && z === 0) continue;
          const bp = pos.offset(x, y, z).floored();
          const b = this.bot.blockAt(bp);
          if (b && b.name && b.name !== 'air') {
            blocks.push({
              name: b.name,
              x: bp.x, y: bp.y, z: bp.z,
              hardness: b.hardness,
              displayName: b.displayName
            });
          }
        }
      }
    }
    return blocks.slice(0, 50);
  }

  _biome() {
    try {
      const bp = this.bot.entity.position.floored();
      return this.bot.blockAt(bp)?.biome?.name || '';
    } catch { return ''; }
  }
}

module.exports = PerceptionCollector;
