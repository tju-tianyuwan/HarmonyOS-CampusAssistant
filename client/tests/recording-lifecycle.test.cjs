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

function quickStartSetup() {
  const h = setup();
  h.context.GlobalState.isTeacher = () => true;
  h.context.GlobalState.course = { id: 1 };
  h.page.recordState = 'idle'; h.page.recordingActive = false;
  h.page.startOnAppear = true;
  h.page.start = async () => h.events.push('start-capture');
  h.page.onStartRequestConsumed = () => h.events.push('request-consumed');
  return h;
}

test('one-tap start is consumed once before capture, even if appearance repeats', () => {
  const { page, events } = quickStartSetup();
  page.consumeStartRequest(); page.consumeStartRequest();
  assert.deepEqual(events, ['request-consumed', 'start-capture']);
});

test('normal page appearance never starts recording automatically', () => {
  const { page, events } = quickStartSetup(); page.startOnAppear = false;
  page.consumeStartRequest(); assert.deepEqual(events, []);
});

test('recovered recording is never replaced or resumed by a pending quick-start', () => {
  const { page, events } = quickStartSetup();
  page.recordState = 'paused'; page.recordingActive = true;
  page.consumeStartRequest();
  assert.deepEqual(events, ['request-consumed']); assert.equal(page.recordState, 'paused');
});

test('invalid course, student identity or unavailable cache cannot auto-start capture', () => {
  for (const condition of ['course', 'role', 'cache']) {
    const { page, context, events } = quickStartSetup();
    if (condition === 'course') context.GlobalState.course = null;
    if (condition === 'role') context.GlobalState.isTeacher = () => false;
    if (condition === 'cache') page.recordingStore = null;
    page.consumeStartRequest(); assert.deepEqual(events, ['request-consumed'], condition);
  }
});

function realtimeSetup() {
  const h = setup();
  const files = new Map();
  h.page.realtime = true;
  h.page.seq = 0;
  h.page.pendingBuffers = [];
  h.page.recordingStore = {
    appendRealtime(seq, data) {
      const previous = files.get(seq) || new Uint8Array(0);
      const joined = new Uint8Array(previous.byteLength + data.byteLength);
      joined.set(previous); joined.set(new Uint8Array(data), previous.byteLength);
      files.set(seq, joined);
    },
    save(draft) { h.draft = draft; },
    readFrame(seq, offset) { return files.get(seq).slice(offset, offset + 6400).buffer; },
    remove(seq) { files.delete(seq); },
    finish() {}
  };
  h.files = files;
  return h;
}

test('realtime PCM windows split exactly at 60 seconds and recovery seals the active window', () => {
  const h = realtimeSetup();
  h.page.pendingBuffers = [new Uint8Array(1920000 + 3200).buffer];
  h.page.cacheBuffers();
  assert.equal(h.files.get(0).byteLength, 1920000);
  assert.equal(h.files.get(1).byteLength, 3200);
  assert.equal(h.page.seq, 1);
  assert.equal(h.page.realtimeBytes, 3200);
  assert.equal(h.draft.nextSeq, 2);
  assert.equal(h.draft.realtime, true);
});

test('realtime cache failure retains unsaved PCM instead of losing microphone data', () => {
  const h = realtimeSetup();
  h.page.pendingBuffers = [new Uint8Array(3200).buffer];
  h.page.recordingStore.appendRealtime = () => { throw new Error('disk full'); };
  assert.throws(() => h.page.cacheBuffers(), /disk full/);
  assert.equal(h.page.pendingBuffers[0].byteLength, 3200);
  assert.equal(h.page.seq, 0);
  assert.equal(h.page.uploadQueue.length, 0);
});

test('realtime pause seals partial window before waiting for active uploader', async () => {
  const h = realtimeSetup();
  h.page.pendingBuffers = [new Uint8Array(3200).buffer];
  h.page.flushChunk = h.context.RecordPage.prototype.flushChunk;
  h.page.drainRealtime = async () => {
    assert.equal(h.page.seq, 1);
    assert.equal(h.page.realtimeBytes, 0);
  };
  await h.page.flushChunk(true);
  assert.equal(h.files.get(0).byteLength, 3200);
});

test('lost commit acknowledgement is retried without duplicating visible transcript', async () => {
  const h = realtimeSetup();
  h.context.Api.token = 'token';
  h.page.pendingBuffers = [new Uint8Array(3200).buffer];
  h.page.cacheBuffers(); h.page.seq = 1; h.page.realtimeBytes = 0;
  const row = { id: 9, seq: 0, start_ms: 0, end_ms: 100, text: 'saved' };
  h.page.segments = [row];
  h.context.RealtimeRecording = class {
    async open() {}
    committed() { return row; }
    close() {}
    static async delay() {}
  };
  await h.page.drainRealtime();
  assert.equal(h.page.segments.length, 1);
  assert.equal(h.page.uploadQueue.length, 0);
  assert.equal(h.files.size, 0);
});
