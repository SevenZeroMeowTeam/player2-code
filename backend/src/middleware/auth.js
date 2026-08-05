const jwt = require('jsonwebtoken');
const SECRET = process.env.JWT_SECRET || 'dev_secret';

const users = new Map([
  ['admin', { id: 'u_admin', password: 'admin123', role: 'admin' }]
]);

function signToken(user) {
  return jwt.sign(
    { userId: user.id, role: user.role, username: user.username },
    SECRET,
    { expiresIn: '30d' }
  );
}

function verify(token) {
  try { return jwt.verify(token, SECRET); }
  catch { return null; }
}

function login(req, res) {
  const { username, password } = req.body || {};
  const user = users.get(username);
  if (!user || user.password !== password) {
    return res.status(401).json({ error: '账号或密码错误' });
  }
  const token = signToken({ ...user, username });
  res.json({ token, userId: user.id, username, role: user.role });
}

function verifyMiddleware(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  const payload = verify(token);
  if (!payload) return res.status(401).json({ error: '未授权' });
  req.user = payload;
  next();
}

async function socketAuth(socket, next) {
  const token = socket.handshake.auth?.token || socket.handshake.query?.token;
  const payload = verify(token);
  if (!payload) {
    if (process.env.NODE_ENV !== 'production') {
      socket.data = { userId: 'guest_' + socket.id.slice(0, 6), role: 'guest' };
      return next();
    }
    return next(new Error('未授权'));
  }
  socket.data = payload;
  next();
}

module.exports = { login, verify: verifyMiddleware, socketAuth };
