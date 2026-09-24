const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.RECORDING_TEST_TYPESCRIPT || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

function setup(get = async () => JSON.stringify({ entries: [], configured: false, semester_start: '', multiple_semesters: false })) {
  const style = read('common/TimetableStyle.ets').replace(/export /g, '');
  const page = read('pages/TimetablePage.ets').split('  @Builder')[0]
    .replace(/^import .*;\r?\n/gm, '').replace('@Component', '')
    .replace('export struct TimetablePage', 'class TimetablePage')
    .replace(/@(StorageLink|Watch)\('[^']+'\)\s*/g, '').replace(/@(State|Prop)\s*/g, '') + '\n}';
  const context = vm.createContext({ Api: { get }, Date });
  vm.runInContext(ts.transpileModule(style + page + '\nglobalThis.Types = { TimetableStyle, TimetablePage };', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const timetable = new context.Types.TimetablePage();
  timetable.courses = [{ id: 1, name: '离散数学' }, { id: 2, name: '计算机原理' }, { id: 3, name: '个人空间' }];
  timetable.semesterStart = '2026-09-14';
  timetable.weekMonday = new Date(2026, 8, 21).getTime();
  return { page: timetable, style: context.Types.TimetableStyle };
}

function entry(id, fields = {}) {
  return { id, class_course_id: 1, semester_start: '2026-09-14', weekday: 1,
    start_section: 1, end_section: 2, start_week: 1, end_week: 16, week_type: 'all', location: 'A101', ...fields };
}

test('transparent timetable retains exact period geometry and two time-of-day gaps', () => {
  const { style } = setup();
  assert.equal(style.sectionTop(1), 0);
  assert.equal(style.sectionTop(4), 180);
  assert.equal(style.sectionTop(5), 254);
  assert.equal(style.sectionTop(9), 508);
  assert.equal(style.totalHeight(), 748);
  assert.equal(style.blockHeight(1, 1), 52);
  assert.equal(style.blockHeight(1, 2), 112);
  assert.equal(style.blockHeight(4, 5), 126);
});

test('all possible course spans fit inside the canvas and do not overlap adjacent classes', () => {
  const { style } = setup();
  for (let start = 1; start <= 12; start++) {
    for (let end = start; end <= 12; end++) {
      const bottom = style.sectionTop(start) + style.blockHeight(start, end);
      assert.ok(bottom <= style.totalHeight());
      assert.ok(style.blockHeight(start, end) >= 52);
      if (end < 12) assert.ok(style.sectionTop(end + 1) - bottom >= style.CARD_GAP);
    }
  }
});

test('same course has a stable tone; conflict is a separate readable tone', () => {
  const { style } = setup();
  assert.equal(style.tone(12), style.tone(12));
  assert.notEqual(style.tone(12), style.tone(13));
  assert.equal(style.tone(12, true), style.CONFLICT);
  const luminance = hex => {
    const rgb = [1, 3, 5].map(offset => parseInt(hex.slice(offset, offset + 2), 16) / 255)
      .map(v => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4);
    return .2126 * rgb[0] + .7152 * rgb[1] + .0722 * rgb[2];
  };
  for (const tone of [...style.TONES, style.CONFLICT]) {
    for (const surface of [tone.top, tone.bottom]) {
      assert.ok((luminance(surface) + .05) / (luminance(tone.ink) + .05) >= 4.5, JSON.stringify(tone));
    }
  }
});

test('only period labels are repeated; there are no empty white cell surfaces', () => {
  const page = read('pages/TimetablePage.ets');
  const grid = page.split('  weekGrid() {')[1].split('  @Builder')[0];
  assert.equal((grid.match(/ForEach\(SECTIONS/g) || []).length, 1);
  assert.ok(!grid.includes("'#BFFFFFFF'"));
  assert.ok(!grid.includes("'#E8EFEB'"));
  assert.ok(!page.includes(".backgroundColor('#FFFFFF')"));
  assert.match(page, /DAY_DIVIDER/);
  assert.match(grid, /border\(\{ width: \{ left: index === 0 \? 0 : 1 \}/);
  assert.match(grid, /TimetableCourseCard\(/);
  const card = read('common/components/TimetableCourseCard.ets');
  assert.match(card, /TouchMotion\.pressedOffset\(this\.reduceMotion, 'card'\)/);
  assert.match(card, /onClick\(this\.onOpen\)/);
});

test('week filtering preserves odd/even rules, semester bounds and course membership', () => {
  const { page } = setup();
  page.entries = [entry(1), entry(2, { week_type: 'odd' }), entry(3, { week_type: 'even' }),
    entry(4, { start_week: 3 }), entry(5, { end_week: 1 }), entry(6, { class_course_id: 99 })];
  assert.deepEqual(Array.from(page.weekEntries(), e => e.id), [1, 3]);
  page.shiftWeek(1);
  assert.deepEqual(Array.from(page.weekEntries(), e => e.id), [1, 2, 4]);
  page.shiftWeek(-1); assert.equal(page.weekNumber(), 2);
});

test('different semester starts still use each course own week number', () => {
  const { page } = setup();
  page.entries = [entry(1, { week_type: 'odd' }), entry(2, { semester_start: '2026-09-07', week_type: 'odd' })];
  assert.deepEqual(Array.from(page.weekEntries(), e => e.id), [2]);
});

test('overlapping chains merge; adjacent periods and different days remain separate', () => {
  const { page } = setup();
  page.entries = [entry(1), entry(2, { start_section: 2, end_section: 4 }),
    entry(3, { start_section: 4, end_section: 6 }), entry(4, { start_section: 7, end_section: 8 }),
    entry(5, { weekday: 2 })];
  const blocks = page.dayBlocks(1);
  assert.equal(blocks.length, 2);
  assert.equal(blocks[0].start, 1); assert.equal(blocks[0].end, 6);
  assert.deepEqual(Array.from(blocks[0].entries, e => e.id), [1, 2, 3]);
  assert.equal(blocks[1].start, 7);
  assert.equal(page.dayBlocks(2).length, 1);
});

test('a course tile opens its detail; a conflict opens all affected entries', () => {
  const { page } = setup();
  const first = entry(1), second = entry(2, { class_course_id: 2 });
  page.openBlock({ start: 1, end: 2, entries: [first] });
  assert.equal(page.selectedCourse.id, 1); assert.equal(page.selectedEntry, first);
  page.selectedCourse = null;
  page.openBlock({ start: 1, end: 2, entries: [first, second] });
  assert.equal(page.conflictingEntries.length, 2); assert.equal(page.selectedCourse, null);
  page.openEntry(second); assert.equal(page.selectedCourse.id, 2); assert.equal(page.conflictingEntries.length, 0);
});

test('courses scheduled in other weeks are not mistaken for unscheduled courses', () => {
  const { page } = setup(); page.entries = [entry(1, { start_week: 5 })];
  assert.deepEqual(Array.from(page.unscheduled(), c => c.id), [2, 3]);
});

test('out-of-order refreshes cannot replace the latest timetable', async () => {
  const pending = [];
  const { page } = setup(() => new Promise(resolve => pending.push(resolve)));
  const old = page.load(), fresh = page.load();
  pending[1](JSON.stringify({ entries: [entry(2)], semester_start: '2026-09-14', configured: true }));
  await fresh;
  pending[0](JSON.stringify({ entries: [entry(1)], semester_start: '2026-09-07', configured: true }));
  await old;
  assert.equal(page.entries[0].id, 2); assert.equal(page.loading, false);
});

test('leaving the timetable discards pending responses; failures stay explicit', async () => {
  let finish;
  const { page } = setup(() => new Promise(resolve => { finish = resolve; }));
  const request = page.load(); page.aboutToDisappear();
  finish(JSON.stringify({ entries: [entry(1)], configured: true })); await request;
  assert.equal(page.entries.length, 0);
  const failed = setup(async () => { throw new Error('offline'); }).page;
  await failed.load(); assert.match(failed.error, /offline/); assert.equal(failed.loading, false);
});
