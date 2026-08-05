class ClientRegistry {
  constructor() {
    this.bridges = new Map();      // userId -> socket
    this.webClients = new Map();   // userId -> socket
    this.socketToUser = new Map(); // socketId -> { userId, type }
  }

  registerBridge(userId, socket) {
    this.bridges.set(userId, socket);
    this.socketToUser.set(socket.id, { userId, type: 'bridge' });
  }

  registerWeb(userId, socket) {
    this.webClients.set(userId, socket);
    this.socketToUser.set(socket.id, { userId, type: 'web' });
  }

  unregister(socketId) {
    const meta = this.socketToUser.get(socketId);
    if (!meta) return;
    if (meta.type === 'bridge') this.bridges.delete(meta.userId);
    else if (meta.type === 'web') this.webClients.delete(meta.userId);
    this.socketToUser.delete(socketId);
  }

  getBridgeForUser(userId) { return this.bridges.get(userId); }
  getWebForUser(userId) { return this.webClients.get(userId); }

  count() {
    return { bridges: this.bridges.size, webs: this.webClients.size };
  }

  listPublic() {
    return Array.from(this.bridges.entries()).map(([userId, socket]) => ({
      userId, connected: socket.connected
    }));
  }
}

module.exports = ClientRegistry;
