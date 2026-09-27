const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
test('course home and workspace use the same crystal AI button', () => {
  for (const file of ['pages/Index.ets', 'pages/CrystalStudyPage.ets']) {
    assert.match(read(file), /CourseAiButton\(\{/);
  }
  const button = read('common/components/CourseAiButton.ets');
  assert.match(button, /width\(56\)\.height\(56\)\.borderRadius\(22\)/);
  assert.match(button, /StudyMaterial\.light/);
  assert.match(button, /TouchMotion\.press/);
  assert.match(button, /this\.onOpen\(\)/);
});
test('both phone and tablet place AI alongside navigation and remove floating entries', () => {
  const index = read('pages/Index.ets');
  const navigation = index.split('  workbenchSwitcher() {')[1].split('  workbenchTabs() {')[0];
  assert.equal((navigation.match(/CourseAiButton\(\{/g) || []).length, 2);
  assert.equal((navigation.match(/this\.workbenchTabs\(\)/g) || []).length, 2);
  assert.equal((navigation.match(/this\.openRecordPage\(\)/g) || []).length, 2);
  assert.doesNotMatch(index, /Button\('AI 助手'\)|Button\('AI'\)|shouldShowRecordEntry/);
  assert.match(index, /FloatingRecordButton\(\{/);
  assert.match(read('common/components/MobileTabs.ets'), /opacity\(this\.keys\.includes\(this\.selected\) \? 1 : 0\)/);
});
