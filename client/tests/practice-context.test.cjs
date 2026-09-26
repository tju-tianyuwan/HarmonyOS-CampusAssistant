const assert=require('node:assert/strict');
const {test}=require('node:test');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const ts=require(process.env.RECORDING_TEST_TYPESCRIPT||'typescript');
const root=path.resolve(__dirname,'../entry/src/main/ets');
const source=fs.readFileSync(path.join(root,'pages/PracticePage.ets'),'utf8').split('  @Builder')[0]
  .replace(/^import .*;\r?\n/gm,'').replace('@Component','').replace('export struct PracticePage','class PracticePage')
  .replace(/@StorageLink\('[^']+'\)\s*/g,'').replace(/@State\s+/g,'')+'\n}\nglobalThis.Page=PracticePage;';
const compiled=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;
const contextData={class_course_id:7,course_name:'高等数学',session_id:null,session_title:'',knowledge_count:1,
  topics:[{name:'函数极限',source_count:1}],knowledge_sources:['提纲：极限']};
function setup(api={get:async()=>JSON.stringify(contextData)}){
  const state={course:{name:'高等数学'},courseId:()=>7,userId:()=>2,currentSessionId:-1};
  const sandbox=vm.createContext({GlobalState:state,Api:api,promptAction:{showToast:()=>{}},clearTimeout});
  vm.runInContext(compiled,sandbox);
  const page=new sandbox.Page();
  page.active=true;page.scopeCourseId=7;page.scopeUserId=2;page.scopeSessionId=-1;
  return {page,state};
}
test('initial state never shows the data-structures demo',()=>{
  const {page}=setup();
  assert.equal(page.questionBank.length,0);assert.equal(page.questionIndexes.length,0);
  assert.equal(page.topics.join(','),'综合');assert.equal(page.progressWidth(),'0%');
  assert.equal(source.includes('二叉树'),false);
});
test('metadata comes from selected course and reset clears old quiz state',async()=>{
  const {page}=setup();page.answeredTotal=3;page.correctTotal=2;page.selectedTopic='old';
  await page.loadContext();
  assert.equal(page.topics.join(','),'综合,函数极限');assert.equal(page.scopeTitle,'高等数学');
  assert.equal(page.answeredTotal,0);assert.equal(page.correctTotal,0);assert.equal(page.selectedTopic,'综合');
  assert.equal(page.contextLoading,false);
});
test('empty and unavailable courses do not fall back to sample questions',async()=>{
  const {page}=setup({get:async()=>JSON.stringify({...contextData,knowledge_count:0,topics:[],knowledge_sources:[]})});
  await page.loadContext();assert.equal(page.knowledgeCount,0);assert.equal(page.questionBank.length,0);
  const broken=setup({get:async()=>{throw Error('offline');}}).page;
  await broken.loadContext();assert.match(broken.contextError,/offline/);assert.equal(broken.topics.join(','),'综合');
});
test('late course response cannot populate a different course',async()=>{
  let resolve;const {page,state}=setup({get:()=>new Promise(r=>resolve=r)});
  const pending=page.loadContext();state.courseId=()=>8;
  resolve(JSON.stringify(contextData));await pending;
  assert.equal(page.topics.join(','),'综合');assert.equal(page.knowledgeCount,0);
});
test('metadata response after leaving the page is ignored',async()=>{
  let resolve;const {page}=setup({get:()=>new Promise(r=>resolve=r)});
  const pending=page.loadContext();page.aboutToDisappear();resolve(JSON.stringify(contextData));await pending;
  assert.equal(page.topics.join(','),'综合');
});
test('generation is scoped, populates quiz and increments statistics only once',async()=>{
  let body;const question={id:1,type:'单选题',topic:'极限',difficulty:'基础',stem:'test',options:['a','b','c','d'],answer:1,explanation:'why',source:'提纲：极限'};
  const {page}=setup({get:async()=>JSON.stringify(contextData),postLong:async(path,input)=>{
    body=input;return JSON.stringify({questions:[question],knowledge_sources:['提纲：极限']});}});
  await page.loadContext();await page.generateQuestions();
  assert.equal(body.class_course_id,7);assert.equal(body.user_id,2);assert.equal(body.session_id,undefined);
  assert.equal(page.questionBank[0].topic,'极限');assert.equal(page.compactTab,'questions');
  page.chooseAnswer(1);page.submitAnswer();page.submitAnswer();
  assert.equal(page.answeredTotal,1);assert.equal(page.correctTotal,1);
});
test('late generation results are ignored on course change',async()=>{
  let resolve;const {page,state}=setup({get:async()=>JSON.stringify(contextData),postLong:()=>new Promise(r=>resolve=r)});
  await page.loadContext();const pending=page.generateQuestions();state.courseId=()=>8;
  resolve(JSON.stringify({questions:[{id:1}],knowledge_sources:[]}));await pending;
  assert.equal(page.questionBank.length,0);
});
