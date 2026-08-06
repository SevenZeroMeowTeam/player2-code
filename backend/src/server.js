require('dotenv').config();
const express = require('express');
const http = require('http');
const cors = require('cors');
const { Server } = require('socket.io');
const AIOrchestrator = require('./services/aiOrchestrator');
const ClientRegistry = require('./services/clientRegistry');
const authMiddleware = require('./middleware/auth');

const app = express();
const server = http.createServer(app);

app.use(cors());
app.use(express.json());

const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
  pingInterval: 15000,
  pingTimeout: 30000
});

const clientRegistry = new ClientRegistry();
const aiOrchestrator = new AIOrchestrator(
  process.env.AI_API_URL || 'http://ollama:11434/v1',
  process.env.AI_API_KEY,
  process.env.AI_MODEL || 'deepseek-r1:7b'
);

app.get('/health', (req, res) => {
  res.json({ status: 'ok', onlineClients: clientRegistry.count() });
});

app.post('/api/v1/auth/login', authMiddleware.login);
app.get('/api/v1/clients', authMiddleware.verify, (req, res) => {
  res.json({ clients: clientRegistry.listPublic() });
});

io.use(authMiddleware.socketAuth);

io.on('connection', (socket) => {
  const clientType = socket.handshake.query.type || 'unknown';
  const userId = socket.data.userId;

  console.log(`[Connect] ${clientType} user=${userId} socket=${socket.id}`);

  if (clientType === 'bridge') {
    clientRegistry.registerBridge(userId, socket);
  } else if (clientType === 'web') {
    clientRegistry.registerWeb(userId, socket);
  }

  socket.on('player:command', async (data) => {
    const { playerId, command, params } = data;
    const bridge = clientRegistry.getBridgeForUser(userId);
    if (bridge) {
      bridge.emit('player:command', { playerId, command, params, ts: Date.now() });
    }
  });

  socket.on('player:create', async (data) => {
    const { name, serverHost, serverPort, version, mode, personality } = data;
    try {
      const playerId = 'ai_' + Date.now();
      const player = await aiOrchestrator.createPlayer({
        playerId, name, serverHost, serverPort, version, mode, personality, userId
      });
      const bridge = clientRegistry.getBridgeForUser(userId);
      if (bridge) {
        bridge.emit('player:spawn', player);
      }
      socket.emit('player:created', { success: true, player });
    } catch (err) {
      socket.emit('player:created', { success: false, error: err.message });
    }
  });

  socket.on('player:perception', async (data) => {
    const { playerId, perception } = data;
    try {
      const decision = await aiOrchestrator.processPerception(playerId, perception);
      if (decision && decision.actions) {
        const bridge = clientRegistry.getBridgeForUser(userId);
        if (bridge) {
          bridge.emit('player:actions', { playerId, actions: decision.actions, reasoning: decision.reasoning });
        }
        socket.emit('ai:decision', { playerId, decision });
      }
    } catch (err) {
      console.error('[AI Error]', err.message);
    }
  });

  socket.on('player:chat', async (data) => {
    const { playerId, sender, message } = data;
    try {
      const reply = await aiOrchestrator.chat(playerId, sender, message);
      const bridge = clientRegistry.getBridgeForUser(userId);
      if (bridge && reply) {
        bridge.emit('player:say', { playerId, message: reply });
      }
      socket.emit('ai:chat', { playerId, sender, reply });
    } catch (err) {
      console.error('[Chat Error]', err.message);
    }
  });

  socket.on('mod:event', (data) => {
    const webClient = clientRegistry.getWebForUser(userId);
    if (webClient) {
      webClient.emit('mod:event', data);
    }
  });

  socket.on('disconnect', () => {
    clientRegistry.unregister(socket.id);
    console.log(`[Disconnect] socket=${socket.id}`);
  });
});

const PORT = process.env.PORT || 8080;
server.listen(PORT, () => {
  console.log(`[Player2 Backend] Listening on port ${PORT}`);
  console.log(`  AI Gateway: ${process.env.AI_API_URL}`);
});
