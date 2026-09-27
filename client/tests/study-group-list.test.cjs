const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.RECORDING_TEST_TYPESCRIPT || 'typescript');
const original = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/MeetingPage.ets'), 'utf8');
const methods = original.slice(0, original.indexOf('  @Builder')) +
  original.slice(original.indexOf('  private async loadRooms()'), original.indexOf('  build() {'));
const source = methods.replace(/^import .*;\r?\n/gm, '').replace('@Component', '').replace('export struct MeetingPage', 'class MeetingPage')
  .replace(/@StorageLink\('[^']+'\)\s*/g, '').replace(/@(Prop|State)\s*/g, '') + '\n}\nglobalThis.Page = MeetingPage;';
const room = (id, extra = {}) => ({ id, name: '学习小组', status: 'active', joined: true, creator_id: 2, participant_limit: 6, ...extra });
function setup() {
  const calls = [];
  const api = { get: async () => '[]', post: async url => { calls.push(url); return '{}'; }, postLong: async url => { calls.push(url); return JSON.stringify(room(1, { status: 'ended' })); } };
  const context = vm.createContext({ Api: api, GlobalState: { courseId: () => 6, userId: () => 2, canManageCurrentCourse: () => false }, AlertDialog: { show() {} } });
  vm.runInContext(ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, context);
  const page = new context.Page();
  return { page, api, calls };
}
test('list excludes unjoined and ended rooms, retaining ending until completion', async () => {
  const { page, api } = setup(); api.get = async () => JSON.stringify([room(1), room(2, { joined: false }), room(3, { status: 'ended' }), room(4, { status: 'ending' })]);
  await page.loadRooms(); assert.deepEqual(Array.from(page.rooms, r => r.id), [1, 4]);
});
test('leaving clears list and active detail even when list reload fails', async () => {
  const { page, api, calls } = setup(); page.rooms = [room(1)]; page.room = room(1); page.messages = [{ id: 1 }]; page.input = '草稿'; page.minutes = true;
  api.get = async () => { throw Error('网络不可用'); };
  await page.memberAction('leave');
  assert.deepEqual(calls, ['/meetings/1/leave']); assert.equal(page.rooms.length, 0); assert.equal(page.room, null);
  assert.equal(page.messages.length, 0); assert.equal(page.input, ''); assert.equal(page.minutes, false);
});
test('successful end removes immediately; failed end preserves group', async () => {
  const { page, api } = setup(); page.rooms = [room(1)]; page.room = room(1);
  api.postLong = async () => { throw Error('结束失败'); }; await page.action('end');
  assert.equal(page.rooms.length, 1); assert.equal(page.room.id, 1);
  api.postLong = async () => JSON.stringify(room(1, { status: 'ended' })); await page.action('end');
  assert.equal(page.room, null); assert.equal(page.rooms.length, 0);
});
test('poll detects another member ending the group', async () => {
  const { page, api } = setup(); page.rooms = [room(1)]; page.room = room(1);
  api.get = async () => JSON.stringify({ room: room(1, { status: 'ended' }), members: [{ id: 2 }], messages: [], cursor: 0 });
  await page.poll(); assert.equal(page.room, null); assert.equal(page.rooms.length, 0);
});
test('refresh removes nonselected ended rooms and does not require an open detail', async () => {
  const { page, api } = setup(); page.rooms = [room(1), room(2)];
  api.get = async () => JSON.stringify([room(1), room(2, { status: 'ended' })]);
  await page.refreshRooms(); assert.deepEqual(Array.from(page.rooms, r => r.id), [1]);
});
test('late list response cannot resurrect a removed room', async () => {
  const { page, api } = setup(); let finish;
  api.get = () => new Promise(resolve => { finish = resolve; });
  const pending = page.loadRooms(); page.removeRoomFromList(1);
  finish(JSON.stringify([room(1)])); await pending; assert.equal(page.rooms.length, 0);
});
test('selection only opens current membership and never auto-joins a stale room', async () => {
  const { page, calls, api } = setup();
  await page.selectRoom(room(1, { joined: false })); await page.selectRoom(room(1, { status: 'ended' }));
  assert.equal(page.room, null);
  api.get = async () => JSON.stringify({ room: room(1), members: [{ id: 2 }], messages: [], cursor: 0 });
  await page.selectRoom(room(1)); assert.equal(page.room.id, 1); assert.equal(calls.length, 0);
});
test('list filtering is repeated on a fresh page and ignores results after navigation away', async () => {
  const { page, api } = setup(); api.get = async () => JSON.stringify([room(1, { joined: false }), room(2, { status: 'ended' })]);
  await page.loadRooms(); assert.equal(page.rooms.length, 0);
  page.active = false; api.get = async () => JSON.stringify([room(3)]);
  await page.loadRooms(); assert.equal(page.rooms.length, 0);
});
