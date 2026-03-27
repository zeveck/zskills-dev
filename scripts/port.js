/**
 * port.js -- deterministic dev-server port for the current project root.
 *
 * Main repo ({{MAIN_REPO_PATH}}) -> 8080 (backward compatible).
 * Worktrees -> stable port in 9000-60000 derived from the project root path.
 * DEV_PORT env var overrides everything.
 *
 * Usage:
 *   import { getPort } from './scripts/port.js';   // as module
 *   node scripts/port.js                            // prints port to stdout
 */
import { createHash } from 'node:crypto';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const PROJECT_ROOT = resolve(dirname(__filename), '..');

const MAIN_REPO = '{{MAIN_REPO_PATH}}';
const DEFAULT_PORT = 8080;
const RANGE_START = 9000;
const RANGE_SIZE = 51000; // 9000-60000

export function getPort() {
  if (process.env.DEV_PORT) return parseInt(process.env.DEV_PORT, 10);

  // Main repo gets the default port
  if (MAIN_REPO !== '{{MAIN_REPO_' + 'PATH}}' && PROJECT_ROOT === MAIN_REPO) return DEFAULT_PORT;

  // Worktrees get a deterministic port from their path
  const hash = createHash('md5').update(PROJECT_ROOT).digest();
  return RANGE_START + (hash.readUInt16BE(0) % RANGE_SIZE);
}

// CLI mode: node scripts/port.js
if (resolve(process.argv[1] || '') === __filename) {
  console.log(getPort());
}
