// Generates a test-only page next to local assets, with actual production renderer.
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../../');
const assets=path.join(root,'client/entry/src/main/resources/rawfile/math');
const out=path.join(root,'.codex-run/math-check');
fs.mkdirSync(out,{recursive:true});
const sample=String.raw`# AI 提纲 · 高等数学
## 一、极限与导数
行内公式：$\lim_{x\to0}\frac{\sin x}{x}=1$，以及 \(f'(x)=2x\)。
## 二、积分与求和
$$\int_0^1 x^2\,dx=\frac{1}{3}$$
\[\sum_{k=1}^{n}k=\frac{n(n+1)}{2}\]
## 三、矩阵
$$A=\begin{pmatrix}a&b\\c&d\end{pmatrix}$$
## 四、代码不当公式
\`$this_is_code$\`
<img src="https://invalid.example/tracker" onerror="window.pwned=true">
`.replace(/\\`/g,'`');
const html=fs.readFileSync(path.join(assets,'outline.html'),'utf8')
  .replace('src="outline.js"','src="outline.js"')
  .replace(/(<\/head>)/,'<script defer src="fixture.js"></script>$1');
fs.cpSync(assets,path.join(out,'assets'),{recursive:true});
fs.writeFileSync(path.join(out,'assets/fixture.html'),html);
fs.writeFileSync(path.join(out,'assets/fixture.js'),`window.renderOutline(${JSON.stringify(sample)});document.body.dataset.mathCount=document.querySelectorAll('.katex').length;document.body.dataset.errorCount=document.querySelectorAll('.math-error').length;document.body.dataset.unsafeCount=document.querySelectorAll('img,iframe').length;const result=document.createElement('p');result.textContent='验证：'+document.body.dataset.mathCount+' 个公式，'+document.body.dataset.errorCount+' 个错误，'+document.body.dataset.unsafeCount+' 个外部图片/框架，代码保留：'+(document.querySelector('code')?.textContent==='$this_is_code$');document.body.append(result);`);
console.log(path.join(out,'assets/fixture.html'));
