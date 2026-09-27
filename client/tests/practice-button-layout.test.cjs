const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/PracticePage.ets'), 'utf8');
test('generation button fits inside rounded panel, with settings scrolling independently', () => {
  const panel = source.split('  leftPanel() {')[1].split('  optionItem(')[0];
  const button = panel.split("Button(this.generating ? '正在生成…' : '✦  AI 出题')")[1];
  assert.match(button, /width\('90%'\)/);
  assert.match(button, /maxWidth: 280/);
  assert.match(button, /height\(46\)/);
  assert.match(button, /flexShrink\(0\)/);
  assert.match(button, /margin\(\{ top: 12, bottom: 4 \}\)/);
  assert.match(panel, /layoutWeight\(1\)\.align\(Alignment.Top\)\.scrollBar/);
  assert.doesNotMatch(source, /Scroll\(\) \{ this.leftPanel\(\) \}/);
});
