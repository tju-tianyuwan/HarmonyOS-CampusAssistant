const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/CourseAiPage.ets'), 'utf8');
const ts = require(process.env.RECORDING_TEST_TYPESCRIPT || 'typescript');
test('teacher sends general mode, student remains course single mode', () => {
  assert.match(source, /GlobalState\.isTeacher\(\) \? 'general' : 'single'/);
  assert.match(source, /Text\('通用模型 · 不限课程资料'\)/);
});
test('teacher does not append course memory instructions; student memory stays scoped', () => {
  const method = source.split('  private buildMemory(): string {')[1].split('  private async ensureChatSession')[0];
  const state = { teacher: true };
  const context = vm.createContext({ GlobalState: { isTeacher: () => state.teacher } });
  const compiled = ts.transpileModule('function buildMemory(): string {' + method + '\nglobalThis.memory = buildMemory;', { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
  vm.runInContext(compiled, context);
  const page = { messages: [{ role: 'user', content: '问题' }], speakerName: () => 'AI' };
  assert.equal(context.memory.call(page), '');
  state.teacher = false;
  assert.match(context.memory.call(page), /课程事实仍以知识库片段为准/);
});
