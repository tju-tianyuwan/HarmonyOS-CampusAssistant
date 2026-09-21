const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

// Use the installed SDK compiler; no additional test dependencies are needed.
const ts = require(process.env.RECORDING_TEST_TYPESCRIPT || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const captureSource = fs.readFileSync(path.join(root, 'service/RecordingCapture.ets'), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/export /g, '');
// Exercise actual controller methods, excluding ArkUI's declarative UI syntax.
const pageSource = fs.readFileSync(path.join(root, 'pages/RecordPage.ets'), 'utf8')
  .split('  // ---------- UI ----------')[0]
  .replace(/^import .*;\r?\n/gm, '')
  .replace('@Component', '').replace('export struct RecordPage', 'class RecordPage')
  .replace(/@StorageLink\('[^']+'\)\s*/g, '').replace(/@State\s+/g, '') + '\n}';
const compiled = ts.transpileModule(captureSource + '\n' + pageSource +
  '\nglobalThis.RecordPage = RecordPage;', { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;

function setup() {
  const events = [];
  const context = vm.createContext({
    console: { warn: () => {} }, Scroller: class {},
    GlobalState: {},
    Api: { post: async () => events.push('finish'), get: async () => '[]' }
  });
  vm.runInContext(compiled, context);
  const page = new context.RecordPage();
  page.sessionId = 22;
  page.recordState = 'recording';
  page.recordingActive = true;
  page.toast = message => events.push(message);
  page.stopTimers = () => events.push('timers-stop');
  page.startTimers = () => events.push('timers-start');
  page.flushChunk = async () => events.push('flush');
  page.recordingStore = { finish: () => events.push('cache-finish') };
  page.capturer = {
    stop: async () => events.push('stop'),
    release: async () => events.push('release')
  };
  return { page, events, context };
}

test('normal finish releases capture before upload and server finish', async () => {
  const { page, events } = setup();
  await page.finish();
  assert.deepEqual(events.slice(0, 6), ['timers-stop', 'stop', 'release', 'flush', 'finish', 'cache-finish']);
  assert.equal(page.recordState, 'finished');
  assert.equal(page.recordingActive, false);
  assert.equal(page.capturer, null);
});

test('native System error on stop still releases and saves captured audio', async () => {
  const { page, events } = setup();
  page.capturer.stop = async () => { throw new Error('System error.'); };
  await page.finish();
  assert.ok(events.includes('release'));
  assert.ok(events.includes('finish'));
  assert.equal(page.recordState, 'finished');
});

test('failed release retains capturer and recording cache for retry', async () => {
  const { page, events } = setup();
  page.capturer.stop = async () => { throw new Error('System error.'); };
  page.capturer.release = async () => { throw new Error('System error.'); };
  await page.finish();
  assert.equal(page.recordState, 'recording');
  assert.equal(page.recordingActive, true);
  assert.notEqual(page.capturer, null);
  assert.ok(events.includes('timers-start'));
  assert.ok(!events.includes('finish'));
  assert.ok(!events.includes('cache-finish'));
  assert.equal(page.controlling, false);
  page.capturer.release = async () => {};
  await page.finish();
  assert.equal(page.recordState, 'finished');
});

test('pause then resume creates a new capturer; recovered drafts can also resume', async () => {
  const { page } = setup();
  await page.pauseOrResume();
  assert.equal(page.recordState, 'paused');
  assert.equal(page.capturer, null);
  let initialized = false;
  page.initCapturer = async () => { initialized = true; };
  await page.pauseOrResume();
  assert.ok(initialized);
  assert.equal(page.recordState, 'recording');
});

test('restored paused draft can finish without a native capturer', async () => {
  const { page } = setup();
  page.recordState = 'paused';
  page.capturer = null;
  await page.finish();
  assert.equal(page.recordState, 'finished');
});

test('unuploaded chunks block server finish and survive for retry', async () => {
  const { page, events } = setup();
  page.uploadQueue = [{ seq: 3 }];
  await page.finish();
  assert.equal(page.recordState, 'paused');
  assert.equal(page.uploadQueue.length, 1);
  assert.ok(!events.includes('finish'));
  assert.ok(!events.includes('cache-finish'));
  page.uploadQueue = [];
  await page.finish();
  assert.equal(page.recordState, 'finished');
});

test('cache write errors prevent finish even with an empty upload queue', async () => {
  const { page, events, context } = setup();
  page.flushChunk = context.RecordPage.prototype.flushChunk;
  page.cacheBuffers = () => { throw new Error('disk full'); };
  await page.finish();
  assert.equal(page.recordState, 'paused');
  assert.ok(!events.includes('finish'));
  assert.ok(!events.includes('cache-finish'));
});

test('failed server finish keeps draft for retry without stopping twice', async () => {
  const { page, events, context } = setup();
  context.Api.post = async () => { throw new Error('offline'); };
  await page.finish();
  assert.equal(page.recordState, 'paused');
  assert.ok(!events.includes('cache-finish'));
  context.Api.post = async () => {};
  await page.finish();
  assert.equal(page.recordState, 'finished');
  assert.equal(events.filter(event => event === 'stop').length, 1);
});

test('duplicate finish clicks cannot submit twice', async () => {
  const { page, events } = setup();
  await Promise.all([page.finish(), page.finish()]);
  await page.finish();
  assert.equal(events.filter(event => event === 'finish').length, 1);
});

test('local cleanup failure does not undo a successful server save', async () => {
  const { page } = setup();
  page.recordingStore.finish = () => { throw new Error('cleanup failed'); };
  await page.finish();
  assert.equal(page.recordState, 'finished');
  assert.equal(page.recordingActive, false);
});
