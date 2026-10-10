// Run with NODE_PATH-independent Playwright import supplied via PLAYWRIGHT_MODULE.
// Only isolated synthetic pages are inspected. No screenshots or transcripts saved.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, writeFile, access, rm } from 'node:fs/promises';
import http from 'node:http';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
const pkg = process.argv[2];
assert(pkg?.startsWith('/nix/store/'));
const root = await mkdtemp(path.join(os.tmpdir(), 'hermes-two-factor-'));
const delay = ms => new Promise(r => setTimeout(r, ms));
const exists = async f => access(f).then(() => true, () => false);
const wait = async (test, label) => {
  for (let i = 0; i < 600; i++) { if (await test()) return; await delay(100); }
  throw new Error(`timeout: ${label}`);
};
const freePort = async () => {
  const server = net.createServer();
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  await new Promise(r => server.close(r));
  return port;
};
let context, child;
const fixture = http.createServer((_req, res) => {
  res.end('<!doctype html><label>Verification code<input autocomplete="one-time-code" name="otp" inputmode="numeric"></label>');
});
try {
  await new Promise(r => fixture.listen(0, '127.0.0.1', r));
  const origin = `http://127.0.0.1:${fixture.address().port}`;
  const cdpPort = await freePort();
  context = await chromium.launchPersistentContext(path.join(root, 'profile'), {
    executablePath: process.env.CHROMIUM || 'chromium', headless: true,
    args: [`--remote-debugging-port=${cdpPort}`], viewport: { width: 1440, height: 1000 }
  });
  const target = await context.newPage();
  await target.goto(origin);
  const targets = await fetch(`http://127.0.0.1:${cdpPort}/json/list`).then(r => r.json());
  const cdpTarget = targets.find(t => t.url === origin + '/').webSocketDebuggerUrl;
  const wrapper = await readFile(path.join(pkg, 'bin/hermes'), 'utf8');
  const env = {};
  // Never inherit operator credentials, provider keys, proxy, HOME, or vault env.
  for (const match of wrapper.matchAll(/^export ([A-Z_]+)='([^']*)'$/gm)) env[match[1]] = match[2];
  env.PATH = path.dirname(env.HERMES_NODE) + ':/run/current-system/sw/bin';
  env.HOME = root; env.HERMES_HOME = path.join(root, 'home');
  await import('node:fs/promises').then(fs => fs.mkdir(env.HERMES_HOME, { mode: 0o700 }));
  await writeFile(path.join(env.HERMES_HOME, 'config.yaml'), `model:\n  provider: openrouter\n  default: synthetic-disabled\n  base_url: ${origin}/disabled-model\n`);
  // Non-credential fixture value permits session initialization; no turns run.
  env.OPENROUTER_API_KEY = 'synthetic-not-a-credential';
  env.PYTHONPATH = root + ':' + env.HERMES_PYTHON_SRC_ROOT;
  env.FIXTURE_ROOT = root; env.FIXTURE_ORIGIN = origin;
  env.FIXTURE_CDP_TARGET = cdpTarget; env.FIXTURE_PORT = String(await freePort());
  const harness = fileURLToPath(new URL('./two-factor-dashboard-server.py', import.meta.url));
  // Profile-scoped PTYs spawn their own native gateway. Inject only the
  // synthetic browser boundary/test stimulus there, without replacing it.
  await writeFile(path.join(root, 'sitecustomize.py'), `
import sys, threading, time, runpy
if sys.argv[0] == '-m' or any('tui_gateway' in arg for arg in sys.argv):
    def install_fixture():
        while True:
            module = sys.modules.get('tui_gateway.server')
            if module and hasattr(module, '_methods_onboarding'):
                break
            time.sleep(0.05)
        runpy.run_path(${JSON.stringify(harness)}, run_name='synthetic_fixture')
    threading.Thread(target=install_fixture, daemon=True).start()
`);
  child = spawn(env.HERMES_PYTHON, [harness], { env, cwd: root, stdio: ['ignore', 'ignore', 'pipe'] });
  let diagnostics = '';
  child.stderr.on('data', b => { diagnostics = (diagnostics + b).slice(-16000); });
  const base = `http://127.0.0.1:${env.FIXTURE_PORT}`;
  await wait(() => fetch(base).then(r => r.ok, () => false), 'native dashboard start');
  const page = await context.newPage();
  await page.goto(base + '/chat');
  // Read the real mounted xterm buffer via React's terminal ref. xterm draws
  // on canvas, so innerText is empty. No test-only UI/build substitution.
  const terminalText = () => page.evaluate(() => {
    for (const element of document.querySelectorAll('*')) {
      const key = Object.keys(element).find(k => k.startsWith('__reactFiber$'));
      for (let fiber = key && element[key]; fiber; fiber = fiber.return) {
        for (let hook = fiber.memoizedState; hook; hook = hook.next) {
          const term = hook.memoizedState?.current;
          if (term?.buffer?.active?.getLine) {
            const buffer = term.buffer.active;
            return Array.from({ length: buffer.length }, (_, i) => buffer.getLine(i)?.translateToString(true) || '').join('\n');
          }
        }
      }
    }
    return '';
  });
  try {
    await wait(() => terminalText().then(t => t.includes('Hermes'), () => false), 'real PTY render');
  } catch (error) {
    console.error('Synthetic dashboard initialization failed; no page text retained.');
    throw error;
  }
  await wait(() => terminalText().then(t => t.includes('─ ready')), 'PTY session initialized');
  await delay(1000);
  const focusTerminal = async () => {
    await page.locator('.xterm-helper-textarea').focus();
    // Wait for Ink's input subscription after the rendered overlay commit.
    await delay(250);
  };
  const prompt = async phase => {
    await writeFile(path.join(root, phase + '.start'), 'start');
    try {
      await wait(() => terminalText().then(t => t.includes('Verification code for')), 'masked prompt');
    } catch (error) {
      console.error('Synthetic prompt delivery failed; no server log retained.');
      console.error('Synthetic stage:', await readFile(path.join(root, 'fixture-stage'), 'utf8').catch(() => 'absent'));
      console.error('Synthetic error:', await readFile(path.join(root, 'fixture-error'), 'utf8').catch(() => 'absent'));
      throw error;
    }
  };
  await prompt('submit');
  await focusTerminal();
  await page.keyboard.press('Enter');
  await delay(250);
  assert(!await exists(path.join(root, 'submit.done')), 'empty Return must not answer');
  await page.keyboard.type('654321', { delay: 80 });
  try {
    await wait(() => terminalText().then(t => t.includes('******')), 'masked synthetic input');
  } catch (error) {
    console.error('Synthetic masked-input assertion failed; no rendered text retained.');
    throw error;
  }
  assert(!(await terminalText()).includes('654321'), 'code must not render');
  const canvas = await page.locator('.xterm-screen canvas').first().boundingBox();
  assert(canvas && canvas.width > 0 && canvas.height > 0, 'native prompt canvas must be visible');
  await page.keyboard.press('Enter');
  await wait(() => exists(path.join(root, 'submit.done')), 'browser code callback return');
  assert.equal(await target.locator('input').inputValue(), '654321');
  console.log('PASS request emitted after capability/session attachment; masked PTY prompt; exact string-id value result; browser tool filled fixture');
  await wait(() => terminalText().then(t => !t.includes('Verification code for')), 'submitted prompt closed');
  await prompt('cancel');
  await focusTerminal();
  await page.keyboard.press('Escape');
  await wait(() => exists(path.join(root, 'cancel.done')), 'explicit cancellation');
  assert.equal(await target.locator('input').inputValue(), '654321');
  console.log('PASS explicit cancellation returns code_declined; no implicit approval');
  await wait(() => terminalText().then(t => !t.includes('Verification code for')), 'cancelled prompt closed');
  await target.locator('input').fill('');
  await prompt('replay');
  await page.reload();
  await wait(() => terminalText().then(t => t.includes('Verification code for')), 'reconnected visible prompt');
  assert(!await exists(path.join(root, 'replay.done')), 'reconnect must not autoanswer');
  await focusTerminal();
  await page.keyboard.type('123456', { delay: 80 });
  await page.keyboard.press('Enter');
  await wait(() => exists(path.join(root, 'replay.done')), 'reconnect reply');
  assert.equal(await target.locator('input').inputValue(), '123456');
  assert.equal(await readFile(path.join(root, 'reply-contract'), 'utf8'), 'exact-string-id-value-result');
  assert.equal(await readFile(path.join(root, 'request-contract'), 'utf8'), 'emitted-after-capability-and-attachment');
  // Independently exercise the actual dashboard WS bridge used by Android:
  // capability negotiation, native session attachment, string-id response,
  // and open_requests replay after socket replacement. No model turn.
  const token = await page.evaluate(() => window.__HERMES_SESSION_TOKEN__);
  const url = base.replace('http:', 'ws:') + '/api/ws?token=' + encodeURIComponent(token);
  const connectRpc = async () => {
    const socket = new WebSocket(url);
    const frames = [];
    socket.addEventListener('message', event => frames.push(JSON.parse(event.data)));
    await new Promise((resolve, reject) => {
      socket.addEventListener('open', resolve, { once: true });
      socket.addEventListener('error', reject, { once: true });
    });
    let seq = 0;
    const request = async (method, params = {}) => {
      const id = ++seq;
      socket.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
      await wait(() => frames.some(f => f.id === id && !f.method), 'RPC result');
      const frame = frames.splice(frames.findIndex(f => f.id === id && !f.method), 1)[0];
      assert(!frame.error, `RPC ${method} failed with integer ${frame.error?.code}`);
      return frame.result;
    };
    await request('client.capabilities', { server_requests: true });
    return { socket, frames, request };
  };
  let rpc = await connectRpc();
  const created = await rpc.request('session.create', { close_on_disconnect: false });
  assert(created.session_id);
  const wsPrompt = async phase => {
    await writeFile(path.join(root, phase + '.start'), 'start');
    await wait(() => rpc.frames.some(f => f.method === 'vault.code'), 'native WS code request');
    const frame = rpc.frames.splice(rpc.frames.findIndex(f => f.method === 'vault.code'), 1)[0];
    assert.equal(typeof frame.id, 'string');
    assert.equal(frame.params.session_id, created.session_id);
    return frame;
  };
  let question = await wsPrompt('ws-submit');
  rpc.socket.send(JSON.stringify({ jsonrpc: '2.0', id: question.id, result: { value: '654321' } }));
  await wait(() => exists(path.join(root, 'ws-submit.done')), 'native WS browser callback');
  assert.equal(await target.locator('input').inputValue(), '654321');
  question = await wsPrompt('ws-cancel');
  rpc.socket.send(JSON.stringify({ jsonrpc: '2.0', id: question.id, result: { value: '' } }));
  await wait(() => exists(path.join(root, 'ws-cancel.done')), 'native WS cancellation');
  question = await wsPrompt('ws-replay');
  const pendingId = question.id;
  await new Promise(resolve => { rpc.socket.addEventListener('close', resolve, { once: true }); rpc.socket.close(); });
  rpc = await connectRpc();
  const resumed = await rpc.request('session.activate', { session_id: created.session_id });
  question = resumed.open_requests.find(f => f.method === 'vault.code');
  assert.equal(question.id, pendingId);
  assert(!await exists(path.join(root, 'ws-replay.done')), 'socket disposal must not autoanswer');
  rpc.socket.send(JSON.stringify({ jsonrpc: '2.0', id: question.id, result: { value: '123456' } }));
  await wait(() => exists(path.join(root, 'ws-replay.done')), 'native WS replay response');
  assert.equal(await target.locator('input').inputValue(), '123456');
  rpc.socket.close();
  console.log('PASS native dashboard WS capability/session attachment, exact reply, cancellation, pending string-id reconnect replay to browser callback');
  // Synthetic-only persistence check; report booleans, not contents.
  const fs = await import('node:fs/promises');
  const walk = async dir => {
    for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
      const p = path.join(dir, entry.name);
      if (entry.isDirectory()) await walk(p);
      else if (entry.isFile()) {
        const bytes = await readFile(p);
        assert(!bytes.includes(Buffer.from('654321')) && !bytes.includes(Buffer.from('123456')), 'synthetic code persisted in Hermes home');
      }
    }
  };
  await walk(env.HERMES_HOME);
  assert(!diagnostics.includes('654321') && !diagnostics.includes('123456'), 'synthetic code logged');
  console.log('PASS reconnect keeps pending prompt; no disposal autoanswer; no codes in Hermes history/logs');
} finally {
  await context?.close();
  if (child && child.exitCode === null) {
    const exited = new Promise(resolve => child.once('exit', resolve));
    child.kill('SIGTERM');
    await Promise.race([exited, delay(10000)]);
    if (child.exitCode === null) {
      child.kill('SIGKILL');
      await exited;
    }
  }
  await new Promise(r => fixture.close(r));
  await rm(root, { recursive: true, force: true });
}
