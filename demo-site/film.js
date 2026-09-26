'use strict';
// Deterministic motion design: production renderer supplies the frame time.
const chapters = [
  {start:0,end:6,kicker:'01 / LEARNING SPACE',title:'让每一次学习，<br>都有<em>自己的空间。</em>',description:'冷白与冰蓝，承载每一次思考。<br>从课程开始，把学习的线索连接起来。',tags:['光感课程首页','四大学习入口'],image:'home',caption:'学习空间 / 当前客户端原生界面',focus:[.525,.08,.46,.52]},
  {start:6,end:12,kicker:'02 / COURSE INTELLIGENCE',title:'让每一个疑问，<br>回到<em>课程之中。</em>',description:'围绕正在学习的内容，理清思路。<br>把提问留在课程里，把理解带走。',tags:['课程知识库','单助手问答'],image:'ai',caption:'课程 AI / 当前客户端问答入口',focus:[.225,.215,.756,.075]},
  {start:12,end:18,kicker:'03 / THINKING TOGETHER',title:'让一种想法，<br>遇见<em>更多可能。</em>',description:'引导、思辨、提问、查漏补缺。<br>四位 AI 学伴，让讨论多一个视角。',tags:['多 AI 讨论','独立学习总结'],image:'group',caption:'AI 学习小组 / 原生角色介绍界面',focus:[.267,.16,.70,.205]},
  {start:18,end:24,kicker:'04 / YOUR OWN UNDERSTANDING',title:'让一瞬间的懂，<br>变成<em>自己的知识。</em>',description:'个人笔记与班级共享，各有其所。<br>让课堂、记录与新的理解连接。',tags:['个人 / 班级笔记','AI / 手写记录'],image:'notes',caption:'笔记工作台 / 当前客户端原生界面',focus:[.51,.22,.455,.355]},
  {start:24,end:32,kicker:'05 / LEARN, THEN KNOW',title:'从<em>「听过了」</em>，<br>到<em>「我懂了」。</em>',description:'选一个答案，也确认一次理解。<br>从题目到解析，把易错点看清楚。',tags:['知识点练习','判题与解析'],image:'practice',caption:'练习示例 / 客户端内置题目与实际判题结果',focus:[.207,.711,.59,.10]}
];
window.FILM_DURATION = 32;
const q = selector => document.querySelector(selector);
const clamp = value => Math.max(0,Math.min(1,value));
// Quintic easing has zero velocity AND acceleration at each end. All movement
// depends on absolute film time, so chapter changes never reset the camera.
const ease = value => { const x=clamp(value); return x*x*x*(x*(x*6-15)+10); };
const mix = (a,b,p) => a+(b-a)*p;
const names = ['home','ai','group','notes','practice','selected','result'];
const screens = names.map((name,index) => {
  const img = index === 0 ? q('#screen-image') : document.createElement('img');
  img.src = `assets/current-${name}.webp`;
  img.className = 'screen-layer';
  img.alt = '当前客户端界面';
  if(index !== 0) q('#screen-content').append(img);
  return img;
});
const copyLayers = chapters.map((chapter,index) => {
  const layer = document.createElement('div');
  layer.className = 'chapter-copy';
  layer.dataset.chapter = index;
  layer.innerHTML = `<div class="kicker"><i></i><span>${chapter.kicker}</span></div><h1>${chapter.title}</h1><p>${chapter.description}</p><div class="tags">${chapter.tags.map(tag=>`<span>${tag}</span>`).join('')}</div><div class="chapter-number"><span>${String(index+1).padStart(2,'0')}</span><i></i><span>05</span></div>`;
  q('#chapter-copy-stack').append(layer);
  return layer;
});
// Keep the outgoing screen fully opaque under the incoming one. Multiplying
// both layers' alpha would cause a dark dip in the middle of every dissolve.
const cuts = [
  {at:6, width:1.3, from:0, to:1, copyFrom:0, copyTo:1},
  {at:12,width:1.3, from:1, to:2, copyFrom:1, copyTo:2},
  {at:18,width:1.3, from:2, to:3, copyFrom:2, copyTo:3},
  {at:24,width:1.3, from:3, to:4, copyFrom:3, copyTo:4},
  {at:26.1,width:.32,from:4,to:5},
  {at:27.4,width:.42,from:5,to:6},
  // Return to the opening composition without a hard GIF-loop seam.
  {at:31.4,width:1.2,from:6,to:0,copyFrom:4,copyTo:0}
];
window.filmReady = Promise.all(screens.map(img=>img.decode())).then(()=>document.fonts.ready);

function drawCopy(index, direction, progress) {
  const stagger = [0,.045,.09,.135,.045];
  const layer = copyLayers[index];
  layer.style.visibility = 'visible';
  [...layer.children].forEach((element,i) => {
    const phase = clamp((progress-stagger[i])/(1-stagger[i]));
    // Clear outgoing letters slightly before incoming letters become readable.
    const opacity = direction === 'out' ? 1-ease(phase/.65) : ease((phase-.27)/.73);
    const movement = direction === 'out' ? -14*ease(phase) : 18*(1-ease(phase));
    Object.assign(element.style, {
      opacity:String(opacity),
      transform:`translate3d(0,${movement}px,0)`,
      filter:`blur(${(1-opacity)*1.4}px)`
    });
  });
}

window.renderFilm = function(time) {
  const t = Math.max(0,Math.min(time,32));
  const index = Math.min(4,Math.max(0,chapters.findIndex(c => t >= c.start && t < c.end)));
  const chapter = chapters[index];
  const local = t-chapter.start;
  let base = 0;
  let transition = null;
  for(const cut of cuts) {
    const start=cut.at-cut.width/2;
    const end=cut.at+cut.width/2;
    if(t >= end) base=cut.to;
    else if(t >= start) { base=cut.from; transition={...cut,progress:(t-start)/cut.width}; break; }
    else break;
  }
  screens.forEach((screen,i) => Object.assign(screen.style, {
    opacity:i===base?'1':'0',zIndex:i===base?'1':'0',
    transform:'scale(1.004)',filter:'none'
  }));
  if(transition) {
    const p=ease(transition.progress);
    const isChapter=transition.copyTo !== undefined;
    Object.assign(screens[transition.to].style,{
      opacity:String(p),zIndex:'2',
      transform:`translate3d(0,${isChapter?(1-p)*7:0}px,0) scale(${1.004+(isChapter?.012:0)*(1-p)})`,
      filter:`blur(${isChapter?(1-p)*.85:0}px)`
    });
    screens[base].style.filter=`blur(${isChapter?p*.55:0}px)`;
  }
  const phase=t/32*Math.PI*2;
  q('#device').style.opacity='1';
  q('#device').style.transform=`perspective(2200px) translate3d(${Math.sin(phase)*3}px,${-Math.sin(phase)*5}px,0) rotateY(${-4.4+Math.sin(phase)*.5}deg) rotateX(${1.6+Math.sin(phase)*.2}deg) rotateZ(${-1+Math.sin(phase)*.12}deg)`;
  q('#screen-content').style.transform=`scale(${1+(1-Math.cos(phase))*.003})`;

  copyLayers.forEach(layer => { layer.style.visibility='hidden'; });
  const textTransition=transition && transition.copyTo !== undefined ? transition : null;
  let copyIndex = t>=32 ? 0 : index;
  if(textTransition) {
    drawCopy(textTransition.copyFrom,'out',textTransition.progress);
    drawCopy(textTransition.copyTo,'in',textTransition.progress);
    copyIndex=textTransition.progress>=.5?textTransition.copyTo:textTransition.copyFrom;
  } else drawCopy(copyIndex,'in',1);
  q('#film-caption').textContent=chapters[copyIndex].caption;
  q('.film-caption').style.opacity=String(textTransition ? .45+.55*Math.abs(2*textTransition.progress-1) : 1);

  const focus=q('#focus-ring');
  const exit=ease((t-30.55)/.5);
  const showFocus=index===4 ? ease((local-4.1)/.65)*(1-exit) : ease((local-1.9)/.65)*(1-ease((local-4.55)/.7));
  const [x,y,w,h]=chapter.focus;
  Object.assign(focus.style,{left:`${x*100}%`,top:`${y*100}%`,width:`${w*100}%`,height:`${h*100}%`,opacity:String(showFocus*.72),transform:`scale(${1+(1-showFocus)*.009})`});
  const touch=q('#touch');
  const touchTime=index===4 && local<2.9 ? 2.0 : 3.3;
  const touchOpacity=index===4 ? Math.pow(Math.max(0,1-Math.abs(local-touchTime)/.38),2) : 0;
  Object.assign(touch.style,{left:index===4 && local<2.9?'48%':'74%',top:index===4 && local<2.9?'50%':'74%',opacity:String(touchOpacity),transform:`translate(-50%,-50%) scale(${1+(1-touchOpacity)*.9})`});
  const detail=q('#detail');
  const reveal=index===4 ? ease((local-4.45)/.85)*(1-exit) : 0;
  detail.style.opacity=String(reveal);
  detail.style.transform=`translate3d(0,${(1-reveal)*18}px,0) scale(${mix(.985,1,reveal)})`;
  q('#detail-label').textContent='THE MOMENT IT CLICKS / 理解发生的瞬间';
  q('#detail-image').style.backgroundImage='url(assets/practice-detail.webp)';
  q('#detail-image').style.backgroundSize='contain';
  q('#detail-caption').textContent='实际点击答案并提交后的客户端反馈';
  q('#timeline').style.width=`${t/32*100}%`;
  return {time:t,base,transition:transition?{from:transition.from,to:transition.to,progress:transition.progress}:null,copyIndex};
};
window.renderFilm(1.2);
