import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Dumb copy for index only (adjust if you want more files)
const esm = resolve('dist/index.js');
const cjs = resolve('dist/index.cjs');
let code = readFileSync(esm, 'utf8');
// super-light shim: replace `export` with `module.exports =` for index-only
// For larger libs, use tsup/rollup. This keeps things ultra-minimal for now.
code = code
  .replace(/^export \{([^}]+)\};?$/m, 'module.exports = { $1 };')
  .replace(/^export default (.*);$/m, 'module.exports.default = $1;');
writeFileSync(cjs, code);
