import { TouchMotion } from '../common/TouchMotion';
import { MarkdownView } from '../common/components/MarkdownView';
import { MotionPage } from '../common/components/MotionPage';
import { promptAction } from '@kit.ArkUI';
import { LearningTheme as AppTheme } from '../common/LearningTheme';
import { MobileLayout } from '../common/MobileLayout';
import { MobileTabs } from '../common/components/MobileTabs';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

const PRACTICE_BG: string = '#F2F7F6';
const PRACTICE_PANEL: string = '#FFFFFF';
const PRACTICE_SOFT: string = '#F5FFFB';
const PRACTICE_BLUE: string = '#155AA5';
const PRACTICE_CYAN: string = '#187E85';
const PRACTICE_AMBER: string = '#95601A';
const PRACTICE_CORAL: string = '#BA4141';
const PRACTICE_VIOLET: string = '#526D83';
const PRACTICE_BORDER: string = 'rgba(31,62,68,0.09)';
const PRACTICE_SHADOW: string = 'rgba(31,62,68,0.10)';

interface PracticeQuestion {
  id: number;
  type: string;
  difficulty: string;
  topic: string;
  stem: string;
  options: string[];
  answer: number;
  explanation: string;
  source: string;
}

interface PracticeGenerationResponse {
  questions: PracticeQuestion[];
  knowledge_sources: string[];
}

interface GeneratePracticeBody {
  class_course_id: number;
  session_id?: number;
  user_id: number;
  count: number;
  mode: string;
  topic: string;
  difficulty: string;
  requirements: string;
}

const PRACTICE_MODES: string[] = ['智能组卷', '章节巩固', '错题强化'];
interface PracticeTopic { name: string; source_count: number; }
interface PracticeContext {
  class_course_id: number;
  course_name: string;
  session_id: number | null;
  session_title: string;
  knowledge_count: number;
  topics: PracticeTopic[];
  knowledge_sources: string[];
}
const PRACTICE_DIFFICULTIES: string[] = ['综合', '基础', '适中', '进阶'];


@Component
export struct PracticePage {
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  @State selectedMode: string = '智能组卷';
  @State selectedTopic: string = '综合';
  @State selectedDifficulty: string = '综合';
  @State requirementText: string = '';
  @State questionBank: PracticeQuestion[] = [];
  @State questionIndexes: number[] = [];
  @State currentIndex: number = 0;
  @State selectedAnswers: number[] = [];
  @State submittedFlags: boolean[] = [];
  @State topics: string[] = ['综合'];
  @State knowledgeSources: string[] = [];
  @State contextLoading: boolean = false;
  @State contextError: string = '';
  @State knowledgeCount: number = 0;
  @State scopeTitle: string = '';
  private topicMetadata: PracticeTopic[] = [];
  private active: boolean = false;
  private requestVersion: number = 0;
  private scopeCourseId: number = -1;
  private scopeUserId: number = -1;
  private scopeSessionId: number = -1;
  @State answeredTotal: number = 0;
  @State correctTotal: number = 0;
  @State generating: boolean = false;
  @State compact: boolean = false;
  @State compactTab: string = 'questions';
  @State questionViewportHeight: number = 0;
  @State pageReady: boolean = false;
  private introTimer: number = -1;

  aboutToAppear(): void {
    this.active = true;
    this.scopeCourseId = GlobalState.courseId();
    this.scopeUserId = GlobalState.userId();
    this.scopeSessionId = GlobalState.currentSessionId;
    this.scopeTitle = this.courseName();
    this.loadContext();
    this.pageReady = true;
  }

  aboutToDisappear(): void {
    this.active = false;
    this.requestVersion++;
    if (this.introTimer >= 0) {
      clearTimeout(this.introTimer);
      this.introTimer = -1;
    }
  }

  private courseName(): string {
    return GlobalState.course === null ? '当前课程' : GlobalState.course.name;
  }

  private currentQuestion(): PracticeQuestion {
    return this.questionBank[this.questionIndexes[this.currentIndex]];
  }

  private isCurrentRequest(version: number): boolean {
    return this.active && version === this.requestVersion && GlobalState.courseId() === this.scopeCourseId &&
      GlobalState.userId() === this.scopeUserId && GlobalState.currentSessionId === this.scopeSessionId;
  }

  private async loadContext(): Promise<void> {
    const version = ++this.requestVersion;
    this.contextLoading = true;
    this.contextError = '';
    this.questionBank = [];
    this.questionIndexes = [];
    this.selectedAnswers = [];
    this.submittedFlags = [];
    this.currentIndex = 0;
    this.answeredTotal = 0;
    this.correctTotal = 0;
    this.selectedTopic = '综合';
    this.topics = ['综合'];
    this.topicMetadata = [];
    this.knowledgeSources = [];
    this.knowledgeCount = 0;
    try {
      const sessionQuery = this.scopeSessionId > 0 ? `&session_id=${this.scopeSessionId}` : '';
      const data = JSON.parse(await Api.get(`/practice/context?class_course_id=${this.scopeCourseId}${sessionQuery}`)) as PracticeContext;
      if (!this.isCurrentRequest(version)) { return; }
      if (data.class_course_id !== this.scopeCourseId || (data.session_id ?? -1) !== this.scopeSessionId) {
        throw new Error('课程信息不匹配，请重新进入课程');
      }
      this.topicMetadata = data.topics;
      this.topics = ['综合', ...data.topics.map((topic: PracticeTopic) => topic.name).filter((name: string) => name !== '综合')];
      this.knowledgeSources = data.knowledge_sources;
      this.knowledgeCount = data.knowledge_count;
      this.scopeTitle = data.session_title === '' ? data.course_name : `${data.course_name} · ${data.session_title}`;
    } catch (e) {
      if (this.isCurrentRequest(version)) { this.contextError = `课程信息加载失败：${(e as Error).message}`; }
    } finally {
      if (this.isCurrentRequest(version)) { this.contextLoading = false; }
    }
  }

  private statusText(): string {
    if (this.contextLoading) { return '正在读取当前课程'; }
    if (this.contextError !== '') { return '课程信息加载失败'; }
    if (this.generating) { return 'AI 正在组题'; }
    if (this.questionIndexes.length > 0) { return '题组已就绪'; }
    return this.knowledgeCount > 0 ? '请选择知识点并生成练习' : '暂无可出题的课程资料';
  }

  private blankNumbers(count: number, value: number): number[] {
    const result: number[] = [];
    for (let i = 0; i < count; i++) {
      result.push(value);
    }
    return result;
  }

  private blankBooleans(count: number): boolean[] {
    const result: boolean[] = [];
    for (let i = 0; i < count; i++) {
      result.push(false);
    }
    return result;
  }

  private async generateQuestions(): Promise<void> {
    if (!this.isCurrentRequest(this.requestVersion) || this.generating || this.contextLoading || this.contextError !== '' || this.knowledgeCount === 0) {
      return;
    }
    const version = ++this.requestVersion;
    const selectedTopic = this.selectedTopic;
    this.generating = true;
    const body: GeneratePracticeBody = {
      class_course_id: this.scopeCourseId,
      user_id: this.scopeUserId,
      session_id: this.scopeSessionId > 0 ? this.scopeSessionId : undefined,
      count: 5,
      mode: this.selectedMode,
      topic: this.selectedTopic,
      difficulty: this.selectedDifficulty,
      requirements: this.requirementText.trim()
    };
    try {
      const response: PracticeGenerationResponse = JSON.parse(
        await Api.postLong('/practice/generate', body)) as PracticeGenerationResponse;
      if (!this.isCurrentRequest(version)) { return; }
      if (response.questions.length === 0) {
        throw new Error('后端未返回有效题目');
      }
      this.questionBank = response.questions;
      this.knowledgeSources = response.knowledge_sources;
      const next: number[] = [];
      for (let i = 0; i < response.questions.length; i++) {
        next.push(i);
      }
      this.currentIndex = 0;
      this.questionIndexes = next;
      this.selectedAnswers = this.blankNumbers(next.length, -1);
      this.submittedFlags = this.blankBooleans(next.length);
      this.answeredTotal = 0;
      this.correctTotal = 0;
      this.compactTab = 'questions';
      promptAction.showToast({ message: `已生成 ${next.length} 道${selectedTopic}练习题` });
    } catch (e) {
      if (this.isCurrentRequest(version)) {
        promptAction.showToast({ message: `生成题目失败：${(e as Error).message}`, duration: 3500 });
      }
    } finally {
      if (this.isCurrentRequest(version)) { this.generating = false; }
    }
  }

  private currentSelectedAnswer(): number {
    return this.selectedAnswers[this.currentIndex] ?? -1;
  }

  private currentSubmitted(): boolean {
    return this.submittedFlags[this.currentIndex] ?? false;
  }

  private chooseAnswer(index: number): void {
    if (this.questionIndexes.length === 0 || this.currentSubmitted()) {
      return;
    }
    const next: number[] = this.selectedAnswers.slice();
    next[this.currentIndex] = index;
    this.selectedAnswers = next;
  }

  private submitAnswer(): void {
    if (this.questionIndexes.length === 0 || this.currentSelectedAnswer() < 0 || this.currentSubmitted()) {
      return;
    }
    const correct: boolean = this.currentSelectedAnswer() === this.currentQuestion().answer;
    const next: boolean[] = this.submittedFlags.slice();
    next[this.currentIndex] = true;
    this.submittedFlags = next;
    this.answeredTotal += 1;
    if (correct) {
      this.correctTotal += 1;
    }
  }

  private progressWidth(): string {
    if (this.questionIndexes.length === 0) {
      return '0%';
    }
    return `${Math.round((this.currentIndex + 1) * 100 / this.questionIndexes.length)}%`;
  }

  private goQuestion(index: number): void {
    if (index >= 0 && index < this.questionIndexes.length) {
      this.currentIndex = index;
    }
  }

  private optionLabel(index: number): string {
    const labels: string[] = ['A', 'B', 'C', 'D'];
    return labels[index] ?? `${index + 1}`;
  }

  private optionBorderColor(index: number): string {
    const question: PracticeQuestion = this.currentQuestion();
    if (this.currentSubmitted()) {
      if (index === question.answer) {
        return AppTheme.SUCCESS;
      }
      if (index === this.currentSelectedAnswer()) {
        return AppTheme.DANGER;
      }
    }
    return index === this.currentSelectedAnswer() ? PRACTICE_BLUE : AppTheme.DIVIDER;
  }

  private optionBackground(index: number): string {
    const question: PracticeQuestion = this.currentQuestion();
    if (this.currentSubmitted()) {
      if (index === question.answer) {
        return AppTheme.PRIMARY_LIGHT;
      }
      if (index === this.currentSelectedAnswer()) {
        return '#FFF0F0';
      }
    }
    return index === this.currentSelectedAnswer() ? '#EEF4FF' : PRACTICE_PANEL;
  }

  private optionTextColor(index: number): string {
    const question: PracticeQuestion = this.currentQuestion();
    if (this.currentSubmitted() && index === question.answer) {
      return AppTheme.PRIMARY_DEEP;
    }
    if (this.currentSubmitted() && index === this.currentSelectedAnswer() && index !== question.answer) {
      return AppTheme.DANGER;
    }
    return AppTheme.TEXT_PRIMARY;
  }

  private questionResultText(): string {
    return this.currentSelectedAnswer() === this.currentQuestion().answer ? '回答正确' : '再看一步解析';
  }

  private questionResultColor(): string {
    return this.currentSelectedAnswer() === this.currentQuestion().answer ? AppTheme.SUCCESS : PRACTICE_CORAL;
  }

  @Builder
  modeButton(label: string) {
    Button(label).stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
      .fontSize(AppTheme.FONT_CAPTION)
      .fontWeight(this.selectedMode === label ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.selectedMode === label ? '#FFFFFF' : AppTheme.TEXT_SECONDARY)
      .width('100%')
      .height(38)
      .borderRadius(8)
      .backgroundColor(this.selectedMode === label ? AppTheme.INK : 'transparent')
      .onClick(() => {
        this.selectedMode = label;
      })
  }

  @Builder
  topicButton(label: string) {
    Row() {
      Column()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(this.selectedTopic === label ? AppTheme.PRIMARY : AppTheme.DIVIDER)
      Text(label)
        .fontSize(AppTheme.FONT_BODY)
        .fontWeight(this.selectedTopic === label ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.selectedTopic === label ? AppTheme.INK : AppTheme.TEXT_SECONDARY)
      Blank()
      Text(label === '综合' ? '全部' : `${this.topicMetadata.find((item: PracticeTopic) => item.name === label)?.source_count ?? 0} 份资料`)
        .fontSize(10)
        .fontColor(AppTheme.TEXT_TERTIARY)
    }
    .width('100%')
    .height(42)
    .padding({ left: 12, right: 12 })
    .borderRadius(8)
    .backgroundColor(this.selectedTopic === label ? AppTheme.PRIMARY_LIGHT : 'transparent')
    .onClick(() => {
      this.selectedTopic = label;
    })
  }

  @Builder
  difficultyButton(label: string) {
    Text(label)
      .fontSize(11)
      .fontWeight(this.selectedDifficulty === label ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.selectedDifficulty === label ? '#FFFFFF' : AppTheme.TEXT_SECONDARY)
      .height(32)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .borderRadius(8)
      .backgroundColor(this.selectedDifficulty === label ? PRACTICE_BLUE : '#EEF1F5')
      .onClick(() => {
        this.selectedDifficulty = label;
      })
  }

  @Builder
  answerStatistics() {
    // Read @State inside Text: positional @Builder values retain their initial snapshot.
    Row() {
      Column({ space: 3 }) {
        Text(`${this.answeredTotal}`)
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(PRACTICE_BLUE)
        Text('已答').fontSize(10).fontColor(AppTheme.TEXT_TERTIARY)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Column({ space: 3 }) {
        Text(`${this.correctTotal}`)
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(AppTheme.SUCCESS)
        Text('正确').fontSize(10).fontColor(AppTheme.TEXT_TERTIARY)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Column({ space: 3 }) {
        Text(`${this.answeredTotal === 0 ? 0 : Math.round(this.correctTotal * 100 / this.answeredTotal)}%`)
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(PRACTICE_VIOLET)
        Text('正确率').fontSize(10).fontColor(AppTheme.TEXT_TERTIARY)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').margin({ top: 22, bottom: 22 })
  }

  @Builder
  pageAtmosphere() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 32,
          colors: [
            ['#F8FCFA', 0],
            [PRACTICE_BG, 0.56],
            ['#EEF3FF', 1]
          ]
        })
      Column()
        .width(520)
        .height(360)
        .borderRadius(64)
        .rotate({ angle: -16 })
        .backgroundColor('rgba(5,206,145,0.08)')
        .position({ x: -180, y: -130 })
      Column()
        .width(620)
        .height(300)
        .borderRadius(58)
        .rotate({ angle: 10 })
        .backgroundColor('rgba(63,125,255,0.07)')
        .position({ x: 980, y: 390 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  practiceHeader() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
        Column({ space: 5 }) {
          Row({ space: 8 }) {
            Text('专注练习')
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.BG_WHITE)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(999)
              .backgroundColor(AppTheme.PRIMARY)
            Text(`${this.questionIndexes.length} 道练习`)
              .fontSize(10)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(999)
              .backgroundColor('rgba(18,24,24,0.06)')
          }
          Text('AI 刷题')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK)
          Text(`${this.selectedMode} · ${this.selectedTopic} · ${this.selectedDifficulty}`)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: 8 }) {
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.generating ? PRACTICE_AMBER : AppTheme.SUCCESS)
          Text(this.statusText())
            .fontSize(11)
            .fontColor(AppTheme.TEXT_SECONDARY)
        }
        .height(38)
        .padding({ left: 14, right: 14 })
        .borderRadius(19)
        .backgroundColor('rgba(255,255,255,0.74)')
        .border({ width: 1, color: PRACTICE_BORDER })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 26, right: 22, top: 18, bottom: 18 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(118)
    .clip(true)
    .borderRadius(16)
    .backgroundColor(AppTheme.BG_CARD)
    .border({ width: 1, color: AppTheme.DIVIDER })
  }

  @Builder
  leftPanel() {
    Column() {
      Scroll() {
      Column() {
      Column({ space: 5 }) {
        Text('刷题计划')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.INK)
        Text(this.scopeTitle)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      this.answerStatistics()

      Text('练习模式')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .width('100%')
        .margin({ bottom: 8 })
      Column({ space: 4 }) {
        ForEach(PRACTICE_MODES, (mode: string) => {
          this.modeButton(mode)
        }, (mode: string) => mode)
      }
      .width('100%')

      Text('知识点')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 22, bottom: 8 })
      Scroll() {
      Column({ space: 2 }) {
        ForEach(this.topics, (topic: string) => {
          this.topicButton(topic)
        }, (topic: string) => topic)
      }
      .width('100%')
      }.width('100%').height(150).align(Alignment.Top).scrollBar(BarState.Auto)
      if (this.contextLoading || this.contextError !== '' || this.knowledgeCount === 0) {
        Text(this.contextError !== '' ? this.contextError : this.statusText())
          .fontSize(11).fontColor(AppTheme.TEXT_TERTIARY).width('100%').margin({ top: 6 })
      }

      Text('出题要求')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 20, bottom: 8 })
      TextInput({ text: this.requirementText, placeholder: '如：侧重应用与易错点' })
        .width('100%')
        .height(40)
        .fontSize(11)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .placeholderColor(AppTheme.TEXT_TERTIARY)
        .padding({ left: 12, right: 12 })
        .borderRadius(8)
        .backgroundColor('#F2F5F6')
        .border({ width: 1, color: AppTheme.DIVIDER })
        .onChange((value: string) => {
          this.requirementText = value;
        })

      }.width('100%')
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Auto)

      Button(this.generating ? '正在生成…' : '✦  AI 出题').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
        .fontSize(AppTheme.FONT_BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width('90%')
        .constraintSize({ maxWidth: 280 })
        .height(46)
        .flexShrink(0)
        .margin({ top: 12, bottom: 4 })
        .borderRadius(23)
        .backgroundColor(this.generating ? AppTheme.TEXT_TERTIARY : AppTheme.PRIMARY)
        .enabled(!this.generating && !this.contextLoading && this.contextError === '' && this.knowledgeCount > 0)
        .onClick(() => {
          this.generateQuestions();
        })
    }
    .width(this.compact ? '100%' : 224)
    .height('100%')
    .padding({ left: 22, right: 22, top: 26, bottom: 24 })
    .borderRadius(28)
    .backgroundColor('rgba(255,255,255,0.92)')
    .border({ width: 1.2, color: 'rgba(255,255,255,0.96)' })
    .shadow({ radius: 24, color: PRACTICE_SHADOW, offsetX: 0, offsetY: 10 })
  }

  @Builder
  optionItem(option: string, index: number) {
    Row({ space: 14 }) {
      Text(this.optionLabel(index))
        .fontSize(AppTheme.FONT_BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor(index === this.currentSelectedAnswer() ||
          (this.currentSubmitted() && index === this.currentQuestion().answer) ? '#FFFFFF' : AppTheme.TEXT_SECONDARY)
        .width(32)
        .height(32)
        .textAlign(TextAlign.Center)
        .borderRadius(16)
        .backgroundColor(this.currentSubmitted() && index === this.currentQuestion().answer ? AppTheme.SUCCESS :
          (index === this.currentSelectedAnswer() ? this.optionBorderColor(index) : '#EEF1F5'))
      Column() {
        MarkdownView({ content: option, autoHeight: true, textColor: this.optionTextColor(index) })
      }.layoutWeight(1).hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 14, right: 16, top: 12, bottom: 12 })
    .borderRadius(16)
    .backgroundColor(this.optionBackground(index))
    .border({ width: 1.2, color: this.optionBorderColor(index) })
    .animation(TouchMotion.selection(this.reduceMotion))
    .enabled(!this.currentSubmitted())
    .onClick(() => {
      this.chooseAnswer(index);
    })
  }

  @Builder
  explanationPanel() {
    Column({ space: 9 }) {
      Row({ space: 8 }) {
        Column()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.questionResultColor())
        Text(this.questionResultText())
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.questionResultColor())
        Blank()
        Text('AI 解析')
          .fontSize(10)
          .fontColor(PRACTICE_VIOLET)
      }
      MarkdownView({ content: this.currentQuestion().explanation, autoHeight: true, textColor: AppTheme.TEXT_SECONDARY })
    }
    .width('100%')
    .padding(18)
    .margin({ top: 18 })
    .borderRadius(18)
    .backgroundColor(PRACTICE_SOFT)
    .border({ width: 1, color: '#DDF4EB' })
  }

  @Builder
  questionPanel() {
    if (this.questionIndexes.length === 0) {
      Column({ space: 18 }) {
        Text(this.scopeTitle).fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
          .textAlign(TextAlign.Center)
        if (this.contextLoading || this.generating) { LoadingProgress().width(36).height(36) }
        Text(this.contextError !== '' ? this.contextError : this.statusText())
          .fontSize(15).fontColor(AppTheme.TEXT_SECONDARY).textAlign(TextAlign.Center)
        Text(this.knowledgeCount > 0 ? '题目将依据当前课程资料生成，不使用其他课程的示例题。' :
          '请先由教师发布本课程提纲或补充知识库资料，再开始练习。')
          .fontSize(13).fontColor(AppTheme.TEXT_TERTIARY).textAlign(TextAlign.Center)
        if (this.contextError !== '') {
          Button('重新加载').onClick(() => { this.loadContext(); })
        } else if (this.knowledgeCount > 0) {
          Button(this.generating ? '正在生成…' : '生成本课练习').enabled(!this.generating)
            .onClick(() => { this.generateQuestions(); })
        }
      }.width('100%').constraintSize({ minHeight: this.questionViewportHeight })
        .justifyContent(FlexAlign.Center).padding(28).borderRadius(24).backgroundColor('rgba(255,255,255,0.94)')
    } else {
    Column() {
      Row({ space: 8 }) {
        Text(this.currentQuestion().type)
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRACTICE_BLUE)
          .padding({ left: 9, right: 9, top: 4, bottom: 4 })
          .borderRadius(999)
          .backgroundColor('#EEF4FF')
        Text(this.currentQuestion().difficulty)
          .fontSize(10)
          .fontColor(PRACTICE_AMBER)
          .padding({ left: 9, right: 9, top: 4, bottom: 4 })
          .borderRadius(999)
          .backgroundColor('#FFF7E8')
        Text(this.currentQuestion().topic)
          .fontSize(10)
          .fontColor(AppTheme.PRIMARY_DEEP)
          .padding({ left: 9, right: 9, top: 4, bottom: 4 })
          .borderRadius(999)
          .backgroundColor(AppTheme.PRIMARY_LIGHT)
        Blank()
        Text(MobileLayout.studentPhone() ? '' : this.currentQuestion().source)
          .fontSize(10)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
      .width('100%')

      MarkdownView({ content: this.currentQuestion().stem, autoHeight: true,
        textSize: MobileLayout.studentPhone() ? 18 : 21, textColor: AppTheme.INK, bold: true })
        .margin({ top: 18, bottom: 22 })

      Column({ space: 10 }) {
        ForEach(this.currentQuestion().options, (option: string, index: number) => {
          this.optionItem(option, index)
        }, (option: string, index: number) => `${this.currentQuestion().id}_${index}`)
      }
      .width('100%')

      if (this.currentSubmitted()) {
        this.explanationPanel()
      }

      Blank()

      Row({ space: 10 }) {
        Button('‹').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
          .fontSize(24)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .width(42)
          .height(42)
          .borderRadius(21)
          .backgroundColor('#EEF1F5')
          .enabled(this.currentIndex > 0)
          .onClick(() => {
            this.goQuestion(this.currentIndex - 1);
          })
        Button('›').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
          .fontSize(24)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .width(42)
          .height(42)
          .borderRadius(21)
          .backgroundColor('#EEF1F5')
          .enabled(this.currentIndex < this.questionIndexes.length - 1)
          .onClick(() => {
            this.goQuestion(this.currentIndex + 1);
          })
        Blank()
        Button(this.currentSubmitted() ? '已提交' : '提交答案').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .width(136)
          .height(42)
          .borderRadius(21)
          .backgroundColor(this.currentSubmitted() ? AppTheme.TEXT_TERTIARY : PRACTICE_BLUE)
          .enabled(!this.currentSubmitted() && this.currentSelectedAnswer() >= 0)
          .onClick(() => {
            this.submitAnswer();
          })
      }
      .width('100%')
      .margin({ top: 18 })
    }
    .width('100%')
    .constraintSize({ minHeight: this.questionViewportHeight })
    .padding(MobileLayout.studentPhone() ? 14 : { left: 28, right: 28, top: 24, bottom: 22 })
    .borderRadius(24)
    .backgroundColor('rgba(255,255,255,0.94)')
    .border({ width: 1, color: AppTheme.DIVIDER })
    }
  }

  @Builder
  questionNavItem(index: number) {
    Text(`${index + 1}`)
      .fontSize(AppTheme.FONT_BODY)
      .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.currentIndex === index ? '#FFFFFF' :
        (this.submittedFlags[index] ? AppTheme.PRIMARY_DEEP : AppTheme.TEXT_SECONDARY))
      .width(40)
      .height(40)
      .textAlign(TextAlign.Center)
      .borderRadius(12)
      .backgroundColor(this.currentIndex === index ? AppTheme.INK :
        (this.submittedFlags[index] ? AppTheme.PRIMARY_LIGHT : '#EEF1F5'))
      .border({ width: 1, color: this.currentIndex === index ? AppTheme.INK : AppTheme.DIVIDER })
      .stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'tab'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'tab')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
      .onClick(() => {
        this.goQuestion(index);
      })
  }

  @Builder
  rightPanel() {
    Column() {
      Text('本轮进度')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.INK)
        .width('100%')
      Row() {
        Text(`${this.questionIndexes.length === 0 ? 0 : this.currentIndex + 1}`)
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRACTICE_BLUE)
        Text(` / ${this.questionIndexes.length}`)
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_TERTIARY)
        Blank()
        Text(this.selectedMode)
          .fontSize(10)
          .fontColor(PRACTICE_VIOLET)
      }
      .width('100%')
      .margin({ top: 12, bottom: 10 })
      Stack({ alignContent: Alignment.Start }) {
        Column()
          .width('100%')
          .height(6)
          .borderRadius(3)
          .backgroundColor('#E8ECF1')
        Column()
          .width(this.progressWidth())
          .height(6)
          .borderRadius(3)
          .backgroundColor(PRACTICE_BLUE)
      }
      .width('100%')
      .height(6)

      Text('题目导航')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 28, bottom: 12 })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.questionIndexes, (bankIndex: number, index: number) => {
          Row() { this.questionNavItem(index) }.margin({ right: 8, bottom: 8 })
        }, (bankIndex: number, index: number) => `${bankIndex}_${index}`)
      }
      .width('100%')

      Text('难度')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 28, bottom: 10 })
      Row({ space: 6 }) {
        ForEach(PRACTICE_DIFFICULTIES, (difficulty: string) => {
          this.difficultyButton(difficulty)
        }, (difficulty: string) => difficulty)
      }
      .width('100%')

      Column({ space: 10 }) {
        Row() {
          Text('知识点覆盖')
            .fontSize(AppTheme.FONT_BODY)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK)
          Blank()
          Text(this.selectedTopic)
            .fontSize(10)
            .fontColor(AppTheme.PRIMARY_DEEP)
        }
        ForEach(this.knowledgeSources.slice(0, 4), (source: string) => {
          Text(source).fontSize(11).fontColor(AppTheme.TEXT_SECONDARY).width('100%').maxLines(2)
        }, (source: string) => source)
        if (this.knowledgeSources.length === 0) {
          Text('暂无课程资料').fontSize(11).fontColor(AppTheme.TEXT_TERTIARY)
        }
      }
      .width('100%')
      .padding({ top: 18, bottom: 18 })
      .margin({ top: 28 })
      .border({ width: { top: 1, bottom: 1 }, color: AppTheme.DIVIDER })

      Blank()

      Row({ space: 8 }) {
        Column().width(8).height(8).borderRadius(4).backgroundColor(PRACTICE_CYAN)
        Text(this.statusText())
          .fontSize(11)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
      .width('100%')
    }
    .width(this.compact ? '100%' : 224)
    .height('100%')
    .padding({ left: 22, right: 22, top: 26, bottom: 24 })
    .borderRadius(28)
    .backgroundColor('rgba(255,255,255,0.92)')
    .border({ width: 1.2, color: 'rgba(255,255,255,0.96)' })
    .shadow({ radius: 24, color: PRACTICE_SHADOW, offsetX: 0, offsetY: 10 })
  }

  build() {
    Stack() {
      if (this.compact) {
        Column({ space: 8 }) {
          if (MobileLayout.studentPhone()) {
            Row() {
              Text('AI 刷题').fontSize(22).fontWeight(FontWeight.Bold).layoutWeight(1)
              Text(`${this.questionIndexes.length === 0 ? 0 : this.currentIndex + 1} / ${this.questionIndexes.length}`).fontSize(15).fontColor(PRACTICE_BLUE)
            }.width('100%').height(36)
            Row({ space: 16 }) {
              Text(`已答 ${this.answeredTotal}`).fontSize(12).fontColor(PRACTICE_BLUE)
              Text(`正确 ${this.correctTotal}`).fontSize(12).fontColor('#00795C')
              Text(`正确率 ${this.answeredTotal === 0 ? 0 : Math.round(this.correctTotal * 100 / this.answeredTotal)}%`)
                .fontSize(12).fontColor(PRACTICE_VIOLET)
            }.width('100%').padding({ bottom: 8 })
            MobileTabs({ labels: ['答题', '出题', '进度与难度'], keys: ['questions', 'generate', 'difficulty'],
              selected: this.compactTab, onSelect: (key: string) => { this.compactTab = key; } })
          } else {
          Row({ space: 8 }) {
            Button('答题').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).onClick(() => { this.compactTab = 'questions'; })
            Button('出题').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).onClick(() => { this.compactTab = 'generate'; })
            Button('难度').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).onClick(() => { this.compactTab = 'difficulty'; })
          }.width('100%')
          }
          Row() {
            MotionPage({ navigationKey: `0|${this.compactTab}`, tabNavigation: true }) {
            if (this.compactTab === 'generate') {
              this.leftPanel()
            }
            else if (this.compactTab === 'difficulty') {
              Scroll() { this.rightPanel() }.width('100%').height('100%').align(Alignment.Top)
            }
            else {
              Scroll() { this.questionPanel() }.width('100%').height('100%').align(Alignment.Top)
                .onAreaChange((oldArea: Area, newArea: Area) => { this.questionViewportHeight = Number(newArea.height); })
            }
            }
          }.width('100%').layoutWeight(1)
        }.width('100%').height('100%').padding(12)
      } else {
      Row({ space: AppTheme.SPACE_L }) {
        this.leftPanel()

        Column({ space: AppTheme.SPACE_L }) {
          this.practiceHeader()
          Scroll() { this.questionPanel() }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Auto)
            .onAreaChange((oldArea: Area, newArea: Area) => { this.questionViewportHeight = Number(newArea.height); })
        }
        .layoutWeight(1)
        .height('100%')

        this.rightPanel()
      }
      .width('100%')
      .height('100%')
      .padding({ left: AppTheme.SPACE_XXL, right: AppTheme.SPACE_XXL, top: 28, bottom: AppTheme.SPACE_XXL })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG_PAGE)
    .onAreaChange((oldArea: Area, newArea: Area) => { this.compact = Number(newArea.width) < 1000 || Number(newArea.height) < 550; })
  }
}
