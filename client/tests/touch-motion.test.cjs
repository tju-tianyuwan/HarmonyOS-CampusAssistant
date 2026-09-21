const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.RECORDING_TEST_TYPESCRIPT || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');

function motionHarness() {
  let sequence = 0;
  const timers = new Map();
  const animations = [];
  const tokens = fs.readFileSync(path.join(root, 'common/TouchMotion.ets'), 'utf8')
    .replace(/^import .*;\r?\n/gm, '').replace('export class', 'class');
  const component = fs.readFileSync(path.join(root, 'common/components/MotionPage.ets'), 'utf8')
    .split('  build() {')[0]
    .replace(/^import .*;\r?\n/gm, '').replace('@Component', '')
    .replace('export struct MotionPage', 'class MotionPage')
    .replace(/@(Prop|State|BuilderParam|Builder)\s*/g, '')
    .replace(/@(StorageLink|Watch)\('[^']+'\)\s*/g, '') + '\n}';
  const js = ts.transpileModule(tokens + component + '\nglobalThis.Types = { MotionPage, TouchMotion };', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const context = { curves: { cubicBezierCurve: (...args) => args, springMotion: (...args) => args },
    setTimeout: (callback) => { timers.set(++sequence, callback); return sequence; },
    clearTimeout: (id) => timers.delete(id) };
  vm.createContext(context); vm.runInContext(js, context);
  const page = new context.Types.MotionPage();
  page.getUIContext = () => ({ animateTo: (options, callback) => { animations.push(options); callback(); } });
  const go = (key) => { page.navigationKey = key; page.navigate(); };
  const flush = () => { for (const [id, callback] of timers) { timers.delete(id); callback(); } };
  return { page, go, flush, timers, animations, tokens: context.Types.TouchMotion };
}

test('initial display is not hidden behind an entrance timer', () => {
  const { page, timers } = motionHarness(); page.aboutToAppear();
  assert.equal(page.opacityValue, 1); assert.equal(timers.size, 0);
});
test('details enter forwards and return backwards, then settle', () => {
  const h = motionHarness(); h.page.aboutToAppear(); h.go('1|detail');
  assert.equal(h.page.motionOffset, 22); h.flush();
  assert.equal(h.page.motionOffset, 0); assert.equal(h.page.opacityValue, 1);
  h.go('0|list'); assert.equal(h.page.motionOffset, -22); h.flush();
  assert.equal(h.animations.at(-1).duration, 240);
});
test('peer tabs match HTML: fade 120ms without whole-page translation', () => {
  const h = motionHarness(); h.page.navigationKey = '10|class'; h.page.tabNavigation = true;
  h.page.aboutToAppear(); h.go('40|practice');
  assert.equal(h.page.motionOffset, 0); assert.equal(h.page.opacityValue, .65);
  h.flush(); assert.equal(h.animations.at(-1).duration, 120);
});
test('nested note pages retain direction even inside a tab host', () => {
  const h = motionHarness(); h.page.navigationKey = '50|notes|hub'; h.page.tabNavigation = true;
  h.page.aboutToAppear(); h.go('51|notes|personal'); assert.equal(h.page.motionOffset, 22);
});
test('rapid navigation cancels the obsolete pending animation', () => {
  const h = motionHarness(); h.page.aboutToAppear(); h.go('1|a'); h.go('2|b'); h.go('3|c');
  assert.equal(h.timers.size, 1); h.flush(); assert.equal(h.page.opacityValue, 1);
});
test('reduced motion cancels pending work and shows the destination immediately', () => {
  const h = motionHarness(); h.page.aboutToAppear(); h.go('1|detail');
  h.page.reduceMotion = true; h.page.reductionChanged();
  assert.equal(h.timers.size, 0); assert.equal(h.page.motionOffset, 0); assert.equal(h.page.opacityValue, 1);
  h.go('0|list'); assert.equal(h.timers.size, 0);
});
test('page disposal clears pending callbacks', () => {
  const h = motionHarness(); h.page.aboutToAppear(); h.go('1|detail'); h.page.aboutToDisappear();
  assert.equal(h.timers.size, 0);
});
test('large cards do not scale; reduced controls do not move', () => {
  const { tokens } = motionHarness();
  for (const kind of ['button', 'icon', 'tab', 'card']) {
    assert.equal(tokens.pressedScale(true, kind).x, 1);
    assert.equal(tokens.pressedOffset(true, kind).y, 0);
  }
  assert.equal(tokens.pressedScale(false, 'card').x, 1);
  assert.equal(tokens.pressedOffset(false, 'card').y, 1);
  assert.equal(tokens.press(false).duration, 100);
});
