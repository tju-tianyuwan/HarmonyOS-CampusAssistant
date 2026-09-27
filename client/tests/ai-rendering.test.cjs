const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');

test('every AI response surface uses the shared renderer', () => {
  for (const [file, count] of [['CourseAiPage', 2], ['AiNotePage', 2], ['MeetingPage', 2], ['PracticePage', 3]]) {
    const source = read(`pages/${file}.ets`);
    assert.equal((source.match(/MarkdownView\(\{/g) || []).length, count, file);
    assert.doesNotMatch(source, /Text\(m\.content \+/);
  }
  const practice = read('pages/PracticePage.ets');
  assert.doesNotMatch(practice, /Text\(this\.currentQuestion\(\)\.(explanation|stem)\)/);
  assert.match(practice, /layoutWeight\(1\)\.hitTestBehavior\(HitTestMode\.None\)/);
});

test('chat rendering adapts height and streaming without a fixed viewport', () => {
  for (const page of ['CourseAiPage', 'AiNotePage']) {
    const source = read(`pages/${page}.ets`);
    assert.doesNotMatch(source, /=> `[^`]*\$\{m\.content\.length\}/, 'streaming must not recreate Web views per chunk');
    assert.match(source, /content: this\.messages\[index\]\.content/);
  }
  const source = read('common/components/MarkdownView.ets');
  assert.match(source, /this\.autoHeight \? this\.measuredHeight : '100%'/);
  assert.match(source, /Number\.isFinite\(height\)/);
  assert.match(source, /clearTimeout\(this\.refreshTimer\)/);
  assert.match(source, /NestedScrollMode\.PARENT_FIRST/);
  assert.match(source, /JSON\.stringify\(this\.content\)/);
  const renderer = fs.readFileSync(path.resolve(root, '../resources/rawfile/math/outline.js'), 'utf8');
  assert.match(renderer, /ResizeObserver\(reportSize\)/);
  assert.match(renderer, /fonts\.ready\.then\(reportSize\)/);
  assert.match(renderer, /DOMPurify\.sanitize/);
  assert.doesNotMatch(renderer, /scrollTo\(0,0\)/);
});
