const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.RECORDING_TEST_TYPESCRIPT || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const source = fs.readFileSync(path.join(root, 'pages/Index.ets'), 'utf8').split('  @Builder')[0]
  .replace(/^import .*;\r?\n/gm, '').replace('@Entry', '').replace('@Component', '')
  .replace('struct Index', 'class Index').replace(/@(StorageLink|Watch)\('[^']+'\)\s*/g, '')
  .replace(/@State\s*/g, '') + '\n}\nglobalThis.Index = Index;';

function setup(load) {
  const calls = [], saves = [];
  const Api = { BASE_URL: 'http://zhiban.help:8000/api/v1', token: '',
    setAccessToken(value) { this.token = value; },
    async get(route) { calls.push([this.BASE_URL, route, this.token]); return '{"id":5}'; } };
  const context = vm.createContext({ Api, GlobalState: {},
    SessionStore: { load, async save(server, token) { saves.push([server, token]); } } });
  vm.runInContext(ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, context);
  const page = new context.Index();
  page.onContinueRestore = async () => {};
  return { page, Api, calls, saves };
}

test('old custom server and token are ignored without making a network request', async () => {
  const h = setup(async () => ({ server: 'http://10.0.2.2:8000/api/v1', token: 'old-token' }));
  await h.page.restoreAccount();
  assert.equal(h.Api.BASE_URL, 'http://zhiban.help:8000/api/v1');
  assert.equal(h.Api.token, '');
  assert.equal(h.calls.length, 0);
  assert.deepEqual(h.saves, [['http://zhiban.help:8000/api/v1', '']]);
});

test('matching cloud session restores and validates against the fixed backend', async () => {
  const h = setup(async () => ({ server: 'http://zhiban.help:8000/api/v1', token: 'cloud-token' }));
  await h.page.restoreAccount();
  assert.equal(h.page.stage, 'library');
  assert.deepEqual(h.calls, [['http://zhiban.help:8000/api/v1', '/auth/me', 'cloud-token']]);
});

test('a login completed while storage is loading is not overwritten', async () => {
  let release;
  const h = setup(() => new Promise(resolve => { release = resolve; }));
  const restore = h.page.restoreAccount();
  h.Api.setAccessToken('new-login');
  release({ server: 'http://old-server/api/v1', token: 'old-token' });
  await restore;
  assert.equal(h.Api.token, 'new-login');
  assert.equal(h.calls.length, 0);
  assert.equal(h.saves.length, 0);
});
