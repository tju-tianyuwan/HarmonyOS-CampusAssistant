const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.RECORDING_TEST_TYPESCRIPT || 'typescript');
const original = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/AiNotePage.ets'), 'utf8');
const source = original.split('  @Builder')[0].replace(/^import .*;\r?\n/gm, '')
  .replace('@Component', '').replace('export struct AiNotePage', 'class AiNotePage')
  .replace(/@StorageLink\('[^']+'\)\s*/g, '').replace(/@State\s*/g, '') + '\n}\nglobalThis.Page = AiNotePage;';
function setup() {
  const calls = [], messages = [];
  let saved = { id: 5, owner_id: 2, kind: 'md', visibility: 'private', title: '标题', content: '旧内容' };
  const api = {
    put: async (url, body) => { calls.push(['put', url, body]); saved = { ...saved, ...body }; return JSON.stringify(saved); },
    post: async url => { calls.push(['post', url]); saved = { ...saved, visibility: url.endsWith('/unshare') ? 'private' : 'shared', quality_status: 'accepted', quality_score: 8 }; return JSON.stringify(saved); }
  };
  const context = vm.createContext({ Api: api, GlobalState: { userId: () => 2 }, Scroller: class {}, promptAction: { showToast: value => messages.push(value.message) } });
  vm.runInContext(ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, context);
  const page = new context.Page();
  page.myNotes = [saved]; page.selectedNoteIndex = 0; page.editorText = saved.content; page.noteTitle = saved.title;
  return { page, api, calls, messages };
}
test('dirty MD saves current content before sharing and reflects returned visibility', async () => {
  const { page, calls, messages } = setup(); page.editorText = '# 新内容'; page.dirty = true;
  await page.toggleShare();
  assert.deepEqual(calls.map(c => c[0]), ['put', 'post']);
  assert.equal(calls[0][2].content, '# 新内容');
  assert.equal(calls[1][1], '/notes/5/share');
  assert.equal(page.currentNote().visibility, 'shared');
  assert.equal(page.dirty, false); assert.equal(page.sharing, false);
  assert.match(messages.at(-1), /已入知识库/);
});
test('save failure never publishes old content', async () => {
  const { page, api, calls } = setup(); page.dirty = true;
  api.put = async () => { throw Error('保存失败'); };
  await page.toggleShare();
  assert.equal(calls.length, 0); assert.equal(page.dirty, true);
  assert.equal(page.saving, false); assert.equal(page.sharing, false);
});
test('read-only and other owners cannot share', async () => {
  const { page, calls } = setup(); page.readOnly = true; await page.toggleShare();
  page.readOnly = false; page.myNotes[0].owner_id = 3; await page.toggleShare();
  assert.equal(calls.length, 0);
});
test('unshare preserves unsaved draft and uses unshare API', async () => {
  const { page, calls } = setup(); page.myNotes[0].visibility = 'shared'; page.dirty = true; page.editorText = '草稿';
  await page.toggleShare();
  assert.equal(calls.length, 1); assert.equal(calls[0][1], '/notes/5/unshare');
  assert.equal(page.editorText, '草稿'); assert.equal(page.dirty, true);
  assert.equal(page.currentNote().visibility, 'private');
});
test('repeated taps and switching notes cannot race an in-flight share', async () => {
  const { page, api } = setup(); let finish; let count = 0;
  api.post = () => { count++; return new Promise(resolve => { finish = resolve; }); };
  const pending = page.toggleShare(); await page.toggleShare(); page.selectNote(1);
  assert.equal(count, 1); assert.equal(page.selectedNoteIndex, 0);
  finish(JSON.stringify({ ...page.currentNote(), visibility: 'shared' })); await pending;
  assert.equal(page.sharing, false);
});
test('mobile and tablet editors both expose the handwriting-style button', () => {
  assert.equal((original.match(/this\.shareButton\(\)/g) || []).length, 2);
  assert.match(original, /this\.compact \? AppTheme\.PRIMARY_LIGHT/);
  assert.match(original, /AppTheme\.SUCCESS/);
});

test('existing personal and shared notes open in rendered reading mode', () => {
  const { page } = setup();
  page.selectNote(0);
  assert.equal(page.noteBodyMode, 'preview');
  page.readOnly = true; page.myNotes[0].content = ''; page.selectNote(0);
  assert.equal(page.noteBodyMode, 'preview');
  page.setNoteBodyMode('edit');
  assert.equal(page.noteBodyMode, 'preview');
});

test('new empty notes open in editing mode; mode switching preserves unsaved Markdown', () => {
  const { page, calls } = setup(); page.myNotes[0].content = ''; page.selectNote(0);
  assert.equal(page.noteBodyMode, 'edit');
  const markdown = '# 随堂笔记\n**重点**：\\(x^2=4\\)';
  page.editorText = markdown; page.dirty = true; page.selStart = 2; page.selEnd = 5;
  page.setNoteBodyMode('preview');
  assert.equal(page.editorText, markdown); assert.equal(page.dirty, true);
  assert.equal(page.selStart, 0); assert.equal(page.selEnd, 0);
  page.setNoteBodyMode('edit');
  assert.equal(page.editorText, markdown); assert.equal(page.dirty, true);
  assert.equal(calls.length, 0);
});

test('switching notes resets old selection and chooses appropriate body mode', () => {
  const { page } = setup();
  page.myNotes.push({ ...page.myNotes[0], id: 6, content: '' });
  page.selectNote(1); assert.equal(page.noteBodyMode, 'edit');
  page.selStart = 3; page.selEnd = 9;
  page.selectNote(0); assert.equal(page.noteBodyMode, 'preview');
  assert.equal(page.selStart, 0); assert.equal(page.selEnd, 0);
});

test('body preview and source editor share one draft with explicit mode controls', () => {
  assert.match(original, /labels: \['阅读', '编辑'\]/);
  assert.match(original, /!this\.canEditCurrent\(\) \|\| this\.noteBodyMode === 'preview'/);
  assert.match(original, /MarkdownView\(\{ content: this\.editorText\.trim\(\)/);
  assert.match(original, /TextArea\(\{ text: this\.editorText/);
  assert.match(original, /this\.noteBodyMode === 'edit' && this\.selEnd/);
});
