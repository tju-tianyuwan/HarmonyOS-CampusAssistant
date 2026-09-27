const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.RECORDING_TEST_TYPESCRIPT || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const source = read('pages/Index.ets').split('  @Builder')[0]
  .replace(/^import .*;\r?\n/gm, '').replace('@Entry', '').replace('@Component', '')
  .replace('struct Index', 'class Index')
  .replace(/@(StorageLink|Watch)\('[^']+'\)\s*/g, '').replace(/@State\s*/g, '') +
  '\n}\nglobalThis.Index = Index;';

function shell() {
  const state = { isTeacher: () => true, course: { id: 1 }, beforeLeaveClass: null, updateSnapshot: () => {} };
  const context = vm.createContext({ GlobalState: state });
  vm.runInContext(ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, context);
  const page = new context.Index(); page.restoring = false; page.stage = 'workspace';
  return { page, state };
}

test('teacher floating recording entry spans every course tab and detail', () => {
  const { page } = shell();
  for (const tab of ['overview', 'class', 'course_ai', 'ai_meeting', 'materials']) {
    page.currentTab = tab; page.classSubPage = 'list'; page.materialSessionId = 9;
    assert.equal(page.hasTeacherRecordEntry(), true, tab);
    assert.equal(page.shouldShowStudentAiEntry(), false, 'no student AI entry for teacher');
  }
});

test('recording screen, signed-out screens and no active course do not show the FAB', () => {
  const { page, state } = shell();
  page.currentTab = 'class'; page.classSubPage = 'record';
  assert.equal(page.hasTeacherRecordEntry(), false);
  page.currentTab = 'overview';
  for (const stage of ['login', 'library']) {
    page.stage = stage; assert.equal(page.hasTeacherRecordEntry(), false);
  }
  page.stage = 'workspace'; state.course = null;
  assert.equal(page.hasTeacherRecordEntry(), false);
  state.course = { id: 1 }; page.restoring = true;
  assert.equal(page.hasTeacherRecordEntry(), false);
});

test('students retain the existing AI entry and never get the recording FAB', () => {
  const { page, state } = shell(); state.isTeacher = () => false;
  assert.equal(page.hasTeacherRecordEntry(), false);
  assert.equal(page.shouldShowStudentAiEntry(), true);
  page.currentTab = 'course_ai'; assert.equal(page.shouldShowStudentAiEntry(), true);
});

test('one tap requests immediate recording; repeated tap cannot enqueue another start', () => {
  const { page } = shell(); page.currentTab = 'ai_meeting';
  page.openRecordPage(true);
  assert.equal(page.currentTab, 'class'); assert.equal(page.classSubPage, 'record');
  assert.equal(page.recordStartRequested, true);
  page.recordStartRequested = false;
  page.openRecordPage(true); assert.equal(page.recordStartRequested, false);
});

test('dirty course edits must permit navigation before recording can be requested', () => {
  const { page, state } = shell(); page.currentTab = 'materials';
  let proceed;
  state.beforeLeaveClass = done => { proceed = done; };
  page.openRecordPage(true);
  assert.equal(page.currentTab, 'materials'); assert.equal(page.recordStartRequested, false);
  proceed(); assert.equal(page.currentTab, 'class'); assert.equal(page.recordStartRequested, true);
});

test('ordinary recording page entry does not start capture and active recording blocks reentry', () => {
  const { page } = shell(); page.openRecordPage();
  assert.equal(page.recordStartRequested, false);
  page.currentTab = 'overview'; page.recordingActive = true;
  page.openRecordPage(true);
  assert.equal(page.currentTab, 'overview'); assert.equal(page.recordStartRequested, false);
});

test('FAB is rooted outside MotionPage, respects overlays, and content reserves bottom clearance', () => {
  const index = read('pages/Index.ets');
  assert.equal((index.match(/FloatingRecordButton\(\{/g) || []).length, 1);
  assert.match(index, /this\.hasTeacherRecordEntry\(\) && !this\.showSettings && !this\.crystalDetailOpen && !this\.recordingActive/);
  assert.match(index, /padding\(\{ bottom: this\.hasTeacherRecordEntry\(\) \? 80 : 0 \}\)/);
  assert.match(index, /onRecord: \(\) => \{ this\.openRecordPage\(true\); \}/);
  const button = read('common/components/FloatingRecordButton.ets');
  assert.match(button, /\.width\(104\)\.height\(56\)/);
  assert.match(button, /TouchMotion\.press\(this\.reduceMotion\)/);
  assert.match(read('pages/CrystalStudyPage.ets'), /right: GlobalState\.isTeacher\(\) && this\.compact \? 132 : 18/);
});
