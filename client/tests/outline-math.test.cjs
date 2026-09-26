const assert=require('node:assert/strict');
const {test}=require('node:test');
const path=require('node:path');
const math=path.resolve(__dirname,'../entry/src/main/resources/rawfile/math');
const {mathToken}=require(path.join(math,'outline.js'));
const katex=require(path.join(math,'katex/katex.min.js'));
test('supports all four delimiters before Markdown eats backslashes',()=>{
  for(const [source,block,formula] of [
    ['$x_i^2$',false,'x_i^2'],['\\(\\frac{1}{2}\\)',false,'\\frac{1}{2}'],
    ['$$\\int_0^1 x^2\\,dx$$',true,'\\int_0^1 x^2\\,dx'],
    ['\\[\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}\\]',true,'\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}']]){
    const token=mathToken(source,block);assert.equal(token.expression,formula);
    const html=katex.renderToString(token.expression,{displayMode:token.display,throwOnError:true,trust:false});
    assert.match(html,/katex/);assert.match(html,/mathml/);
  }
});
test('block environments and escaped dollars preserve expression',()=>{
  assert.equal(mathToken('\\begin{align}a&=b\\\\c&=d\\end{align}',true).display,true);
  assert.equal(mathToken('$a+\\$b$',false).expression,'a+\\$b');
  assert.equal(mathToken('普通文字',false),undefined);
  assert.equal(mathToken('$ 100',false),undefined);
});
test('unclosed math stays readable and unsupported TeX does not crash the renderer',()=>{
  assert.equal(mathToken('$$x+y',true),undefined);
  assert.throws(()=>katex.renderToString('\\unknowncommand{x}',{throwOnError:true}));
});
