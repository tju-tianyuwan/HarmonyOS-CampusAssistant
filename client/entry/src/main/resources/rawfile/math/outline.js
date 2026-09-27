(function (root) {
  'use strict';
  // Tokenize math BEFORE Markdown consumes backslashes, underscores or matrix rows.
  function mathToken(source, block) {
    let text=source, lead='';
    if (block) { lead=(source.match(/^ {0,3}/)||[''])[0]; text=source.slice(lead.length); }
    const delimiters=block ? [['$$','$$',true],['\\[','\\]',true]] :
      [['$$','$$',true],['\\[','\\]',true],['\\(','\\)',false],['$','$',false]];
    for (const [open,close,display] of delimiters) {
      if (!text.startsWith(open)) continue;
      if (open==='$' && (/^\s/.test(text.slice(1)) || text.startsWith('$$'))) continue;
      let end=open.length;
      while ((end=text.indexOf(close,end))!==-1) {
        let slashes=0;
        for(let j=end-1;j>=0&&text[j]==='\\';j--) slashes++;
        if(slashes%2===0) break;
        end+=close.length;
      }
      if(end<0) continue;
      const expression=text.slice(open.length,end);
      if(!expression.trim() || (open==='$' && (/\n/.test(expression)||/\s$/.test(expression)))) continue;
      const raw=lead+text.slice(0,end+close.length);
      return {type:block?'blockMath':'inlineMath',raw,expression,display};
    }
    if(block) {
      const begin=text.match(/^\\begin\{(equation\*?|align\*?|gather\*?|aligned|cases|matrix|[pbBvV]matrix)\}/);
      if(begin) {
        const closing='\\end{'+begin[1]+'}', end=text.indexOf(closing,begin[0].length);
        if(end>=0) return {type:'blockMath',raw:lead+text.slice(0,end+closing.length),expression:text.slice(0,end+closing.length),display:true};
      }
    }
    return undefined;
  }
  if(typeof module!=='undefined') module.exports={mathToken};
  if(!root.document) return;
  const slots=[];
  const escape=text=>text.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  const parser=new root.marked.Marked({gfm:true,breaks:true});
  const renderToken=token=>{
    const index=slots.push(token)-1;
    return `<span class="math-slot ${token.display?'math-display':'math-inline'}" data-math-index="${index}"></span>`;
  };
  parser.use({renderer:{html(token){return escape(token.text);}},extensions:[
    {name:'blockMath',level:'block',start(src){return src.search(/(?:^|\n) {0,3}(?:\$\$|\\\[|\\begin\{)/);},
      tokenizer(src){return mathToken(src,true);},renderer:renderToken},
    {name:'inlineMath',level:'inline',start(src){return src.search(/\$|\\[([]/);},
      tokenizer(src){return mathToken(src,false);},renderer:renderToken}
  ]});
  root.configureMarkdown=function(embedded,size,color,bold){
    const body=root.document.body;
    body.classList.toggle('embedded',!!embedded);
    body.style.fontSize=Math.max(12,Math.min(28,Number(size)||16))+'px';
    body.style.color=color;
    body.style.fontWeight=bold?'600':'400';
  };
  function reportSize(){
    if(!root.document.body.classList.contains('embedded') || !root.markdownSize) return;
    const height=root.document.getElementById('outline').getBoundingClientRect().height;
    root.markdownSize.resize(Math.ceil(height),root.innerWidth);
  }
  if(root.ResizeObserver) new root.ResizeObserver(reportSize).observe(root.document.getElementById('outline'));
  if(root.document.fonts) root.document.fonts.ready.then(reportSize);
  root.renderOutline=function(markdown){
    const target=root.document.getElementById('outline');
    slots.length=0;
    const text=String(markdown||'');
    try {
      target.innerHTML=root.DOMPurify.sanitize(parser.parse(text),{
        FORBID_TAGS:['img','iframe','object','embed','form','input','style','script'],
        FORBID_ATTR:['href','src','style','srcset','action','id'],ALLOW_DATA_ATTR:true
      });
      target.querySelectorAll('.math-slot').forEach(node=>{
        const token=slots[Number(node.dataset.mathIndex)];
        if(!token)return;
        try {
          root.katex.render(token.expression,node,{displayMode:token.display,throwOnError:true,
            trust:false,strict:'ignore',maxSize:20,maxExpand:1000,output:'htmlAndMathml'});
        } catch(error) {
          node.textContent=token.raw;
          node.classList.add('math-error');
          node.title='此公式暂不支持，已保留原文';
        }
      });
      reportSize();
      return true;
    } catch(error) {
      target.textContent=text;
      reportSize();
      return false;
    }
  };
})(typeof window==='undefined'?globalThis:window);
