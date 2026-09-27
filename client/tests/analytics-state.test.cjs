const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const ts = require(process.env.RECORDING_TEST_TYPESCRIPT || 'typescript');
const raw = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/CourseAiPage.ets'), 'utf8');
const source = raw.split('  @Builder')[0].replace(/^import[\s\S]*?;\r?\n/gm, '')
  .replace('@Component', '').replace('export struct CourseAiPage', 'class CourseAiPage')
  .replace(/@StorageLink\('[^']+'\)\s*/g, '').replace(/@State\s+/g, '') + '\n}\nglobalThis.Page = CourseAiPage;';
const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
const data = { class_course_id: 6, total_questions: 2, missed_count: 0, updated_at: '2026-09-26T12:00:00',
  top_keywords: [{ keyword: '映射', count: 1, missed_count: 0, examples: [], heat: 100, level: '高' }], hot_zones: [] };
function setup(get = async () => JSON.stringify(data)) {
  const state = { isTeacher: () => true, courseId: () => 6, userId: () => 7 };
  const sandbox = vm.createContext({ GlobalState: state, Api: { get }, AppTheme: {},
    Scroller: class {}, promptAction: { showToast() {} }, clearTimeout, clearInterval });
  vm.runInContext(compiled, sandbox);
  const page = new sandbox.Page(); page.analyticsActive = true;
  return { page, state };
}
test('unknown metrics are not zero; course 564883 counts update from response', async () => {
  const { page } = setup(); assert.equal(page.totalQuestionValue, '—');
  await page.loadAnalytics();
  assert.equal(page.totalQuestionValue, '2'); assert.equal(page.missedQuestionValue, '0');
  assert.equal(page.topQuestionValue, '1'); assert.equal(page.topMissedValue, '0');
  assert.equal(page.topMissedRatioValue, '0%'); assert.equal(page.analyticsError, '');
});
test('keyword missed ratio uses keyword denominator, not whole course', async () => {
  const { page } = setup(async () => JSON.stringify({ ...data, total_questions: 10, missed_count: 2,
    top_keywords: [{ ...data.top_keywords[0], count: 4, missed_count: 2 }] }));
  await page.loadAnalytics(); assert.equal(page.missedRatioValue, '20%'); assert.equal(page.topMissedRatioValue, '50%');
});
test('failed request does not render fabricated zero and retry recovers', async () => {
  let failed = true;
  const { page } = setup(async () => { if (failed) throw Error('403'); return JSON.stringify(data); });
  await page.loadAnalytics(); assert.match(page.analyticsError, /403/); assert.equal(page.topQuestionValue, '—');
  failed = false; await page.loadAnalytics(); assert.equal(page.totalQuestionValue, '2'); assert.equal(page.analyticsError, '');
});
test('actual empty response displays zero without dividing by zero', async () => {
  const { page } = setup(async () => JSON.stringify({ ...data, total_questions: 0, top_keywords: [] }));
  await page.loadAnalytics(); assert.equal(page.totalQuestionValue, '0'); assert.equal(page.topMissedRatioValue, '0%');
});
test('response for another course or departed page is ignored', async () => {
  for (const leave of [false, true]) {
    let resolve; const { page, state } = setup(() => new Promise(r => resolve = r));
    const pending = page.loadAnalytics();
    if (leave) page.aboutToDisappear(); else state.courseId = () => 8;
    resolve(JSON.stringify(data)); await pending; assert.equal(page.totalQuestionValue, '—');
  }
});
test('numeric builders read reactive fields instead of capturing initial argument values', () => {
  assert.match(raw, /Text\(metric === 'total' \? this.totalQuestionValue : this.missedQuestionValue\)/);
  assert.match(raw, /Text\(metric === 'topCount' \? this.topQuestionValue/);
  assert.doesNotMatch(raw, /insightMetric\(label: string, value: string/);
});
