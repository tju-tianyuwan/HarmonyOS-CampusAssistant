const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.RECORDING_TEST_TYPESCRIPT || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

function homeHarness({ teacher = true, manager = true, get } = {}) {
  const source = read('pages/CrystalStudyPage.ets').split('  @Builder')[0]
    .replace(/^import .*;\r?\n/gm, '').replace('@Component', '')
    .replace('export struct CrystalStudyPage', 'class CrystalStudyPage')
    .replace(/@StorageLink\('[^']+'\)\s*/g, '').replace(/@(State|Link)\s*/g, '') +
    '\n}\nglobalThis.Home = CrystalStudyPage;';
  const context = vm.createContext({
    GlobalState: { isTeacher: () => teacher, canManageCurrentCourse: () => manager,
      userId: () => 1, courseId: () => 7 },
    Api: { get: get || (async () => JSON.stringify([])) }
  });
  vm.runInContext(ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, context);
  const home = new context.Home(); home.alive = true;
  return home;
}

const sessions = [
  { id: 1, created_at: '2026-09-01', outline_kind: 'official', outline_status: 'published', resource_count: 2 },
  { id: 2, created_at: '2026-09-02', outline_kind: 'official', outline_status: 'draft', resource_count: 3 },
  { id: 3, created_at: '2026-09-03', outline_kind: 'self', outline_status: 'done', resource_count: 0 },
  { id: 4, created_at: '2026-09-04', outline_kind: 'official', outline_status: 'pending', resource_count: 1 }
];

test('teacher and student share the same signed-in palette; signed-out retains its theme', () => {
  const source = read('common/LearningTheme.ets').replace(/^import .*;\r?\n/gm, '')
    .replace('export class', 'class') + '\nglobalThis.Theme = LearningTheme;';
  const context = vm.createContext({ GlobalState: { user: null }, AppTheme: { PRIMARY: '#original' } });
  vm.runInContext(ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, context);
  assert.equal(context.Theme.PRIMARY, '#original');
  for (const role of ['student', 'teacher']) {
    context.GlobalState.user = { role };
    assert.equal(context.Theme.PRIMARY, '#155AA5');
    assert.equal(context.Theme.INK, '#173A56');
    assert.equal(context.Theme.RADIUS_CARD, 24);
  }
});

test('teacher metrics count all visible lessons, pending official outlines and resources', async () => {
  const home = homeHarness({ get: async () => JSON.stringify(sessions) });
  await home.loadLessons();
  assert.equal(home.lessonTotal, 4);
  assert.equal(home.pendingLessons, 2);
  assert.equal(home.resourceTotal, 6);
  assert.deepEqual(Array.from(home.lessons, item => item.id), [4, 3, 2]);
  assert.equal(home.lessonsReady, true);
  assert.equal(home.lessonsError, false);
});

test('student recents still show only published official outlines, even for a personal-space owner', async () => {
  const home = homeHarness({ teacher: false, manager: true, get: async () => JSON.stringify(sessions) });
  await home.loadLessons();
  assert.deepEqual(Array.from(home.lessons, item => item.id), [1]);
});

test('teacher who does not manage the course does not get unpublished recent cards', async () => {
  const home = homeHarness({ manager: false, get: async () => JSON.stringify(sessions) });
  await home.loadLessons();
  assert.deepEqual(Array.from(home.lessons, item => item.id), [1]);
});

test('failed lesson request is explicitly marked unavailable instead of a successful zero', async () => {
  const home = homeHarness({ get: async () => { throw new Error('offline'); } });
  await home.loadLessons();
  assert.equal(home.lessonsReady, true);
  assert.equal(home.lessonsError, true);
  assert.match(read('pages/CrystalStudyPage.ets'), /this\.lessonsReady && !this\.lessonsError \? `\$\{this\.lessonTotal\}` : '—'/);
});

test('leaving a course discards its pending response', async () => {
  let resolve;
  const home = homeHarness({ get: () => new Promise(done => { resolve = done; }) });
  const request = home.loadLessons(); home.aboutToDisappear(); resolve(JSON.stringify(sessions)); await request;
  assert.equal(home.lessonTotal, 0); assert.equal(home.lessons.length, 0);
});

test('teacher navigation retains material ownership and course scheduling guards', () => {
  assert.match(read('pages/Index.ets'), /this\.currentTab === 'materials' && GlobalState\.isTeacher\(\) && GlobalState\.canManageCurrentCourse\(\)/);
  assert.match(read('pages/LibraryPage.ets'), /course\.teacher_id === GlobalState\.userId\(\) && !course\.is_personal/);
  assert.match(read('pages/CrystalStudyPage.ets'), /this\.compact\) \{\s*Column\(\{ space: 12 \}\)/);
  assert.match(read('common/StudyMaterial.ets'), /sdkApiVersion >= 20 && canIUse/);
});
