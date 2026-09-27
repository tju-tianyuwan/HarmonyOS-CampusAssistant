// Run against the actual packaged renderer in the installed browser, without npm dependencies.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const out = path.resolve(__dirname, '../../.codex-run/ai-rendering/browser');
fs.mkdirSync(out, { recursive: true });
fs.cpSync(path.resolve(__dirname, '../entry/src/main/resources/rawfile/math'), path.join(out, 'assets'), { recursive: true });
const sample = String.raw`## 函数与值域
**结论**：\(f(x)=x^2\)，值域为 $[0,+\infty)$。

\[x=\pm\sqrt{y}\]

| 概念 | 说明 |
| --- | --- |
| 原像 | 可以不唯一 |

- 步骤一
- 步骤二



\`const x = 2;\`

<img src="https://invalid.example/track" onerror="window.pwned=true">
<script>window.pwned=true</script>
`.replace(/\\`/g, '`');
const js = `
(async function(){
const checks=[];
const check=(name,ok)=>checks.push({name,ok:!!ok});
const wait=()=>new Promise(resolve=>setTimeout(resolve,150));
let reports=[];
window.markdownSize={resize:(height,width)=>reports.push({height,width})};
window.configureMarkdown(true,16,'#193D55',false);
window.renderOutline(${JSON.stringify(sample)});
await document.fonts.ready; await wait();
check('headings/bold/table/list/code',document.querySelector('h2')&&document.querySelector('strong')&&document.querySelector('table')&&document.querySelectorAll('li').length===2&&document.querySelector('code'));
check('inline and display math',document.querySelectorAll('.katex').length===3&&!document.querySelector('.math-error'));
check('sanitized untrusted HTML',!window.pwned&&!document.querySelector('img')&&document.querySelectorAll('script').length===5);
check('measured nonzero height',reports.some(r=>r.height>100&&r.width>0));
document.body.style.width='260px'; await wait();
check('resized content observed',reports.length>1);
window.renderOutline('正在计算：\\\\[x^2'); await wait();
check('incomplete streamed math stays readable',document.querySelector('main').textContent.includes('x^2'));
window.renderOutline('结果：\\\\[x^2=4\\\\]'); await wait();
check('completed stream renders math',document.querySelectorAll('.katex').length===1);
window.renderOutline('完成'); await wait();
check('short content shrinks',reports.at(-1).height<100);
const result=document.createElement('pre'); result.id='test-result'; result.textContent=JSON.stringify(checks); document.body.append(result);
document.body.dataset.testStatus=checks.every(c=>c.ok)?'PASS':'FAIL';
})();`;
fs.writeFileSync(path.join(out, 'assets/fixture.js'), js);
const html = fs.readFileSync(path.join(out, 'assets/outline.html'), 'utf8').replace('</head>', '<script defer src="fixture.js"></script></head>');
fs.writeFileSync(path.join(out, 'assets/fixture.html'), html);
const browser = process.env.RENDER_TEST_BROWSER || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const result = cp.spawnSync(browser, ['--headless', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
  '--disable-background-networking', '--user-data-dir=' + path.join(out, 'profile'), '--allow-file-access-from-files',
  '--virtual-time-budget=5000', '--dump-dom', 'file:///' + path.join(out, 'assets/fixture.html').replace(/\\/g, '/')],
  { encoding: 'utf8', timeout: 45000, maxBuffer: 4 * 1024 * 1024 });
fs.writeFileSync(path.join(out, 'result.html'), result.stdout || '');
assert.ifError(result.error);
const matches = (result.stdout || '').match(/<pre id="test-result">([\s\S]*?)<\/pre>/);
console.log(matches ? matches[1] : result.stderr);
assert.match(result.stdout || '', /data-test-status="PASS"/, 'Browser renderer checks must all pass; see result.html');
