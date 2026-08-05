require('dotenv').config();
const { io } = require('socket.io-client');
const mineflayer = require('mineflayer');
const PerceptionCollector = require('./perception');
const ActionExecutor = require('./actions');

const CONFIG = {
  backendWS: process.env.BACKEND_WS || 'ws://localhost:8080',
  token: process.env.TOKEN || 'bridge-token',
  mcServer: process.env.MC_SERVER || '127.0.0.1',
  mcPort: parseInt(process.env.MC_PORT || '25565'),
  mcVersion: process.env.MC_VERSION || '1.20.1',
  playerName: process.env.PLAYER_NAME || 'AIPlayer',
  intervalMs: parseInt(process.env.PERCEPTION_INTERVAL_MS || '1500'),
  viewDistance: parseInt(process.env.VIEW_DISTANCE || '4')
};

console.log('[Bridge] Starting Player2 Bridge...');
console.log(`  Backend : ${CONFIG.backendWS}`);
console.log(`  Server  : ${CONFIG.mcServer}:${CONFIG.mcPort} (${CONFIG.mcVersion})`);
console.log(`  Player  : ${CONFIG.playerName}`);

const socket = io(CONFIG.backendWS, {
  auth: { token: CONFIG.token },
  query: { type: 'bridge' },
  reconnection: true,
  reconnectionDelay: 3000,
  transports: ['websocket']
});

let bot = null;
let perceptionCollector = null;
let actionExecutor = null;
let perceptionTimer = null;

function createBot() {
  return new Promise((resolve, reject) => {
    try {
      const b = mineflayer.createBot({
        host: CONFIG.mcServer,
        port: CONFIG.mcPort,
        username: CONFIG.playerName,
        version: CONFIG.mcVersion,
        viewDistance: CONFIG.viewDistance,
        hideErrors: false
      });

      b.once('spawn', () => {
        console.log(`[Bot] Spawned as ${b.username} at ${b.entity.position.toString()}`);
        resolve(b);
      });

      b.on('error', (err) => reject(err));
      b.on('kicked', (reason) => reject(new Error('Kicked: ' + reason)));

      b.on('chat', (username, message) => {
        if (username === b.username) return;
        socket.emit('player:chat', {
          playerId: b.username, sender: username, message
        });
        console.log(`[Chat] <${username}> ${message}`);
      });

      b.on('whisper', (username, message) => {
        socket.emit('player:chat', {
          playerId: b.username, sender: username, message, whisper: true
        });
      });

      b.on('death', () => {
        console.log('[Bot] Died, respawning...');
        setTimeout(() => b.respawn(), 1500);
        socket.emit('mod:event', { type: 'death', player: b.username });
      });

    } catch (err) { reject(err); }
  });
}

async function startPerceptionLoop() {
  if (perceptionTimer) clearInterval(perceptionTimer);
  perceptionTimer = setInterval(async () => {
    if (!bot || !bot.entity) return;
    try {
      const perception = perceptionCollector.collect();
      socket.emit('player:perception', {
        playerId: CONFIG.playerName,
        perception
      });
    } catch (err) {
      console.error('[Perception Error]', err.message);
    }
  }, CONFIG.intervalMs);
}

socket.on('connect', async () => {
  console.log('[Socket] Connected to backend, socketId =', socket.id);

  try {
    bot = await createBot();
    perceptionCollector = new PerceptionCollector(bot, CONFIG.viewDistance);
    actionExecutor = new ActionExecutor(bot);
    startPerceptionLoop();
  } catch (err) {
    console.error('[Bot] Failed to connect:', err.message);
    socket.emit('mod:event', { type: 'error', error: err.message });
  }
});

socket.on('disconnect', () => {
  console.log('[Socket] Disconnected from backend');
  if (perceptionTimer) clearInterval(perceptionTimer);
});

socket.on('player:spawn', (playerConfig) => {
  console.log('[Socket] Spawn requested:', playerConfig);
});

socket.on('player:actions', ({ playerId, actions, reasoning }) => {
  if (!actionExecutor) return;
  console.log(`[Actions] ${actions.length} action(s). Reasoning: ${reasoning || '(none)'}`);
  actionExecutor.execute(actions);
});

socket.on('player:say', ({ playerId, message }) => {
  if (bot) {
    bot.chat(message);
    console.log(`[Bot Say] ${message}`);
  }
});

socket.on('player:command', ({ playerId, command, params }) => {
  if (!actionExecutor) return;
  console.log(`[Direct Command] ${command}`, params);
  switch (command) {
    case 'chat': actionExecutor.chat(params.message); break;
    case 'lookAt': actionExecutor.lookAt(params.x, params.y, params.z); break;
    case 'move': actionExecutor.move(params.direction, params.durationMs); break;
    case 'jump': actionExecutor.jump(); break;
    case 'stop': actionExecutor.stopAll(); break;
    case 'break': actionExecutor.breakBlock(params.x, params.y, params.z); break;
    case 'place': actionExecutor.placeBlock(params.x, params.y, params.z, params.blockName); break;
    case 'attackNearest': actionExecutor.attackNearest(params.type, params.range); break;
    case 'disconnect': if (bot) bot.quit('user command'); break;
  }
});

socket.on('connect_error', (err) => {
  console.error('[Socket Error]', err.message);
});

process.on('SIGINT', () => {
  console.log('\n[Bridge] Shutting down...');
  if (perceptionTimer) clearInterval(perceptionTimer);
  if (bot) bot.quit('bridge shutdown');
  socket.close();
  process.exit(0);
});
