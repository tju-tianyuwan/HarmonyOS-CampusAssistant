'use strict';

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const panel = $('#demo-panel');
const tabs = $$('.demo-tabs [role="tab"]');
const initialNote = '# 二叉树与遍历\n\n中序遍历：左子树 → 根节点 → 右子树。\n\n我的理解：先处理左边，再看自己，最后处理右边。\n\n易错提醒：只有二叉搜索树的中序遍历，才保证得到有序序列。';
const state = { scene: 'class', classTab: 'outline', note: initialNote, savedNote: null, question: 0, groupStep: 0, selection: null, submitted: false };
let toastTimer;
const descriptions = {
  class: ['回到理解发生的那一刻', '教师完成录音、转写与提纲审核后，学生按课次回看。点击提纲或转写，看看课堂内容如何被保留下来。'],
  ai: ['把问题放回课堂里', '围绕课程知识提问。从下方选择一个示例问题，看看课堂知识如何变成容易理解的回答。'],
  group: ['让思考多走一步', '不同角色的 AI 学伴带来不同视角。逐步展开讨论，最后带走一份学习总结。'],
  notes: ['留下自己的理解', '把要点写成自己的笔记。你可以编辑示例内容，在本次页面会话中保存，或下载 Markdown 文件。'],
  practice: ['理解，值得再确认一次', '选一道与本节课相关的题目，作答后查看解析。题目取自客户端现有示例题库。']
};
const questions = [
  { question: '中序遍历到底是什么意思？', answer: '把每个节点当作一个小路口：先走完左边，再访问自己，最后走右边。也就是 <strong>左子树 → 根节点 → 右子树</strong>。这个规则会在每一棵子树中重复。', source: '示例 · 第 05 讲 / 二叉树遍历' },
  { question: '中序遍历一定得到有序结果吗？', answer: '<strong>不一定。</strong>只有当这棵树满足二叉搜索树的性质时，中序遍历才会产生有序序列。普通二叉树的节点值没有这样的大小关系约束。', source: '示例 · 二叉树与二叉搜索树' },
  { question: '能用一个简单例子解释吗？', answer: '假设根节点是 A，左孩子是 B，右孩子是 C。中序遍历先访问 B，再访问 A，最后访问 C，所以结果是 <strong>B → A → C</strong>。试试把“左、根、右”对应到这三个节点。', source: '示例 · 三节点二叉树' }
];
const discussion = [
  ['A', '组员 A · 引导', '先把问题分成两步：遍历规则是什么？这棵树是否满足二叉搜索树的性质？'],
  ['B', '组员 B · 思辨', '如果根节点是 2，左孩子是 3，右孩子是 1，中序结果会是 3、2、1。它并不有序。'],
  ['C', '组员 C · 学习', '我明白了！“左、根、右”描述的是访问顺序，并不直接规定节点值的大小。'],
  ['D', '组员 D · 提醒', '记住条件：二叉搜索树有大小约束，普通二叉树没有。做题时先看树的类型。']
];
const summaryText = '# 二叉树遍历 · 学习总结\n\n## 核心知识点\n中序遍历遵循：左子树 → 根节点 → 右子树。\n\n## 不同理解\n遍历规则约束访问顺序；二叉搜索树的性质约束节点值大小。\n\n## 易错点\n普通二叉树的中序遍历不一定有序。\n\n## 复习建议\n画一棵三节点二叉树，分别写出前序、中序、后序遍历。\n\n---\n智慧伴学产品网页 · 预设演示内容\n';
function escapeHTML(text) { return text.replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char])); }
function toast(message) { clearTimeout(toastTimer); $('#toast').textContent = message; $('#toast').classList.add('visible'); toastTimer = setTimeout(() => $('#toast').classList.remove('visible'), 2800); }
function download(name, content) { const url = URL.createObjectURL(new Blob([content], {type:'text/markdown;charset=utf-8'})); const link = document.createElement('a'); link.href = url; link.download = name; document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000); }
function heading(title, label, subtitle = '') { return `<div class="panel-heading"><div><h3>${title}</h3>${subtitle ? `<p class="panel-subtitle">${subtitle}</p>` : ''}</div><span class="panel-label">${label}</span></div>`; }
function renderClass() {
  return heading('第 05 讲 · 二叉树与遍历', '学生视角') + `<div class="inner-tabs" aria-label="课堂内容"><button data-class-tab="outline" class="${state.classTab === 'outline' ? 'active' : ''}" aria-pressed="${state.classTab === 'outline'}">课程提纲</button><button data-class-tab="transcript" class="${state.classTab === 'transcript' ? 'active' : ''}" aria-pressed="${state.classTab === 'transcript'}">课堂转写</button></div>` + (state.classTab === 'outline'
    ? '<div class="outline-layout"><div class="paper-card"><h4>本节课，我们一起理解</h4><div class="outline-item"><span>01</span> 二叉树的基本概念与结构</div><div class="outline-item"><span>02</span> 前序、中序与后序遍历</div><div class="outline-item"><span>03</span> 二叉搜索树与有序序列</div></div><div class="paper-card"><h4>✦ 本节重点</h4><p>遍历方式的区别，在于根节点何时被访问。</p><div class="key-note">中序遍历<br><strong>左子树 → 根节点 → 右子树</strong></div></div></div>'
    : '<div class="paper-card"><h4>课堂转写片段 · 示例</h4><div class="outline-item"><span>12:08</span> 今天，我们一起理解二叉树的三种遍历。</div><div class="outline-item"><span>12:16</span> 中序遍历先访问左子树，然后是根节点，最后是右子树。</div><div class="outline-item"><span>12:32</span> 注意，普通二叉树的中序遍历不一定得到有序序列。</div></div>') + '<div class="panel-actions"><button class="small-button primary" data-next="ai">这一点没听懂，问问 AI ↗</button></div><p class="scene-hint">教师负责录音与审核发布；学生查看已发布的课程内容。</p>';
}
function renderAI() {
  const q = questions[state.question];
  return heading('课程 AI · 把知识讲明白', '预设问答') + `<div class="chat-bubble user">${q.question}</div><div class="chat-bubble assistant"><b>✦ 智伴 AI</b><p>${q.answer}</p><div class="chat-source">课程内容关联 <span>${q.source}</span></div></div><div class="question-buttons">${questions.map((item, i) => `<button data-question="${i}" aria-pressed="${state.question === i}">${item.question}</button>`).join('')}</div><div class="panel-actions"><button class="small-button" data-next="group">想多听几种思路？进入学习小组 →</button></div>`;
}
function renderGroup() {
  return heading('一个问题，四种视角', '多 AI 讨论', '讨论主题：中序遍历的结果一定有序吗？') + '<div class="group-demo-grid">' + ['A · 引导','B · 思辨','C · 学习','D · 提醒'].map(x=>`<div class="group-demo-person"><b>${x[0]}</b><span>${x.slice(4)}</span></div>`).join('') + '</div>' + discussion.slice(0,state.groupStep).map(([letter,name,content])=>`<div class="group-message"><span>${letter}</span><p><b>${name}</b>${content}</p></div>`).join('') + (state.groupStep === 0 ? '<div class="paper-card"><h4>你发起了一个好问题。</h4><p>“我知道中序遍历是左、根、右，可是为什么有时结果是有序的，有时又不是呢？”</p><p>点击下方按钮，让 AI 学伴接着讨论。</p></div>' : '') + (state.groupStep === 5 ? '<div class="summary-box"><strong>学习总结</strong><br>遍历约束的是访问顺序，二叉搜索树的性质才约束节点值大小。判断结果是否有序，先看题目给的是哪种树。</div>' : '') + `<div class="panel-actions">${state.groupStep < 5 ? `<button class="small-button primary" id="continue-group">${state.groupStep === 0 ? '开始讨论' : state.groupStep < 4 ? '听听下一位学伴的想法 →' : '整理学习总结 ✦'}</button>` : '<button class="small-button primary" id="download-summary">下载学习总结 ↓</button><button class="small-button" data-next="notes">把理解写进笔记 →</button>'}</div>`;
}
function renderNotes() {
  return heading('我的笔记 · 把理解留下来', '个人笔记') + `<label class="editor-label" for="note-content">Markdown 笔记 · 可直接编辑</label><textarea id="note-content" class="note-editor" spellcheck="false">${escapeHTML(state.note)}</textarea><div class="panel-actions"><button class="small-button primary" id="save-note">保存本次笔记</button><button class="small-button" id="download-note">下载 Markdown ↓</button><span class="save-state" id="save-state" role="status">${state.savedNote === state.note ? '✓ 已保存在本次页面会话' : '编辑后可保存或下载'}</span></div><p class="scene-hint">演示笔记保存在页面内存，刷新后恢复初始内容。产品客户端另支持手写笔记与班级共享。</p><div class="panel-actions"><button class="small-button" data-next="practice">记住了？做一道题试试 →</button></div>`;
}
function renderPractice() {
  const options = ['根节点、左子树、右子树','左子树、根节点、右子树','左子树、右子树、根节点','按层从左到右访问'];
  return heading('用一道题，确认你的理解', '单选 · 基础', '知识点：二叉树 / 来自客户端示例题库') + '<p class="quiz-stem">一棵二叉树的中序遍历序列遵循哪一种访问顺序？</p><div class="quiz-options">' + options.map((option,i)=>`<button class="quiz-option${state.selection === i ? ' selected' : ''}${state.submitted && i === 1 ? ' correct' : ''}${state.submitted && state.selection === i && i !== 1 ? ' wrong' : ''}" data-option="${i}" aria-pressed="${state.selection === i}" ${state.submitted ? 'disabled' : ''}><span>${'ABCD'[i]}</span>${option}</button>`).join('') + '</div>' + (state.submitted ? `<div class="quiz-result" role="status"><strong>${state.selection === 1 ? '✓ 答对了！理解又扎实了一点。' : '再想一步，正确答案是 B。'}</strong><br>中序遍历先递归访问左子树，再访问根节点，最后访问右子树。对二叉搜索树执行中序遍历可得到有序序列。</div><div class="panel-actions"><button class="small-button" id="retry-quiz">↻ 再做一次</button><button class="small-button" data-next="ai">回到 AI 问答 →</button></div>` : `<div class="panel-actions"><button class="small-button primary" id="submit-quiz" ${state.selection === null ? 'disabled' : ''}>提交答案 →</button><span class="scene-hint" style="margin:0">选择一个答案，再查看解析</span></div>`);
}
function render() {
  tabs.forEach(tab => { const selected = tab.dataset.scene === state.scene; tab.setAttribute('aria-selected', String(selected)); tab.tabIndex = selected ? 0 : -1; });
  panel.setAttribute('aria-labelledby', `tab-${state.scene}`);
  const desc = descriptions[state.scene];
  $('#scene-description').innerHTML = `<h3>${desc[0]}</h3><p>${desc[1]}</p>`;
  panel.innerHTML = ({class:renderClass, ai:renderAI, group:renderGroup, notes:renderNotes, practice:renderPractice})[state.scene]();
}
function setScene(scene, focusPanel = false) { state.scene = scene; render(); if (focusPanel) panel.focus({preventScroll:true}); }
tabs.forEach((tab, i) => {
  tab.addEventListener('click', () => setScene(tab.dataset.scene));
  tab.addEventListener('keydown', event => { let target; if(event.key === 'ArrowRight') target = (i + 1) % tabs.length; if(event.key === 'ArrowLeft') target = (i + tabs.length - 1) % tabs.length; if(event.key === 'Home') target = 0; if(event.key === 'End') target = tabs.length - 1; if(target !== undefined) { event.preventDefault(); setScene(tabs[target].dataset.scene); tabs[target].focus(); } });
});
panel.addEventListener('click', event => {
  const button = event.target.closest('button'); if(!button) return;
  if(button.dataset.next) return setScene(button.dataset.next, true);
  if(button.dataset.classTab) { state.classTab = button.dataset.classTab; render(); $(`[data-class-tab="${state.classTab}"]`, panel).focus({preventScroll:true}); }
  if(button.dataset.question !== undefined) { state.question = Number(button.dataset.question); render(); $(`[data-question="${state.question}"]`, panel).focus({preventScroll:true}); }
  if(button.id === 'continue-group') { state.groupStep++; render(); ($('#continue-group') || $('#download-summary')).focus({preventScroll:true}); }
  if(button.id === 'download-summary') download('智慧伴学-学习总结.md', summaryText);
  if(button.id === 'save-note') { state.savedNote = state.note; $('#save-state').textContent = '✓ 已保存在本次页面会话'; toast('笔记已保存在本次页面会话'); }
  if(button.id === 'download-note') download('智慧伴学-二叉树笔记.md', state.note);
  if(button.dataset.option !== undefined && !state.submitted) { state.selection = Number(button.dataset.option); render(); $(`[data-option="${state.selection}"]`, panel).focus({preventScroll:true}); }
  if(button.id === 'submit-quiz' && state.selection !== null) { state.submitted = true; render(); $('#retry-quiz').focus({preventScroll:true}); }
  if(button.id === 'retry-quiz') { state.selection = null; state.submitted = false; render(); $('[data-option="0"]', panel).focus({preventScroll:true}); }
});
panel.addEventListener('input', event => { if(event.target.id === 'note-content') { state.note = event.target.value; $('#save-state').textContent = state.savedNote === state.note ? '✓ 已保存在本次页面会话' : '有尚未保存的编辑'; } });
$('#reset-demo').addEventListener('click', () => { Object.assign(state, {scene:'class',classTab:'outline',note:initialNote,savedNote:null,question:0,groupStep:0,selection:null,submitted:false}); render(); toast('学习之旅已重置'); });
$$('[data-open-group]').forEach(link => link.addEventListener('click', () => setScene('group')));
const waveform = $('.waveform');
for(let i=0;i<50;i++) { const bar = document.createElement('i'); bar.style.setProperty('--i',i); bar.style.setProperty('--h',`${8 + ((i * 17 + 11) % 27)}px`); waveform.append(bar); }

const gif = $('#tour-gif');
const gifToggle = $('#toggle-gif');
let playing = false;
let manualGifChoice = false;
function setGifPlayback(value) { playing = value; gif.src = value ? gif.dataset.gif : 'assets/product-tour-poster.jpg'; gifToggle.textContent = value ? 'Ⅱ 暂停动图' : '▶ 播放动图'; gifToggle.setAttribute('aria-pressed',String(value)); }
gifToggle.addEventListener('click', () => { manualGifChoice = true; setGifPlayback(!playing); });
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
if('IntersectionObserver' in window) {
  new IntersectionObserver(entries => { if(!manualGifChoice) setGifPlayback(entries[0].isIntersecting && !reducedMotion.matches); }, {threshold:.2}).observe(gif);
}
reducedMotion.addEventListener('change', event => { if(event.matches) setGifPlayback(false); });
const dialog = $('#image-dialog');
$$('[data-image]').forEach(button => button.addEventListener('click', () => { $('#expanded-image').src = button.dataset.image; $('#expanded-image').alt = `${button.dataset.title}，当前客户端本次新采集截图`; $('#image-title').textContent = button.dataset.title; dialog.showModal(); }));
$('#close-dialog').addEventListener('click', () => dialog.close());
dialog.addEventListener('click', event => { if(event.target === dialog) { const bounds = dialog.getBoundingClientRect(); if(event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close(); } });
render();
