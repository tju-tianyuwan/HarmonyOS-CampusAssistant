import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

const PRACTICE_BG: string = '#F2F7F6';
const PRACTICE_PANEL: string = '#FFFFFF';
const PRACTICE_SOFT: string = '#F5FFFB';
const PRACTICE_BLUE: string = '#3F7DFF';
const PRACTICE_CYAN: string = '#12BFE8';
const PRACTICE_AMBER: string = '#FFB84D';
const PRACTICE_CORAL: string = '#FF6F61';
const PRACTICE_VIOLET: string = '#7A63F3';
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
  user_id: number;
  count: number;
  mode: string;
  topic: string;
  difficulty: string;
  requirements: string;
}

const PRACTICE_MODES: string[] = ['智能组卷', '章节巩固', '错题强化'];
const PRACTICE_TOPICS: string[] = ['综合', '二叉树', '图', '排序'];
const PRACTICE_DIFFICULTIES: string[] = ['综合', '基础', '适中', '进阶'];

const QUESTION_BANK: PracticeQuestion[] = [
  {
    id: 101,
    type: '单选题',
    difficulty: '基础',
    topic: '二叉树',
    stem: '一棵二叉树的中序遍历序列遵循哪一种访问顺序？',
    options: ['根节点、左子树、右子树', '左子树、根节点、右子树', '左子树、右子树、根节点', '按层从左到右访问'],
    answer: 1,
    explanation: '中序遍历先递归访问左子树，再访问根节点，最后访问右子树。对二叉搜索树执行中序遍历可得到有序序列。',
    source: '第 5 讲 · 二叉树遍历'
  },
  {
    id: 102,
    type: '单选题',
    difficulty: '适中',
    topic: '二叉树',
    stem: '含有 n 个节点的完全二叉树采用顺序存储时，编号为 i 的节点左孩子编号通常是？',
    options: ['i + 1', '2i', '2i + 1', 'i / 2'],
    answer: 1,
    explanation: '在节点编号从 1 开始的顺序存储中，节点 i 的左孩子为 2i，右孩子为 2i + 1，父节点为 floor(i / 2)。',
    source: '第 6 讲 · 完全二叉树'
  },
  {
    id: 103,
    type: '概念判断',
    difficulty: '基础',
    topic: '图',
    stem: '无向连通图的任意两个顶点之间都至少存在一条路径。',
    options: ['正确', '错误', '仅完全图正确', '仅树结构正确'],
    answer: 0,
    explanation: '连通图的定义就是任意两个顶点之间均存在路径。完全图要求任意两点之间直接有边，条件更强。',
    source: '第 8 讲 · 图的基本概念'
  },
  {
    id: 104,
    type: '单选题',
    difficulty: '进阶',
    topic: '图',
    stem: '使用邻接表存储含 n 个顶点、e 条边的无向图，其空间复杂度为？',
    options: ['O(n)', 'O(e)', 'O(n + e)', 'O(n²)'],
    answer: 2,
    explanation: '邻接表需要 n 个顶点表节点，并为无向图的每条边保存两个边节点，总空间复杂度为 O(n + e)。',
    source: '第 9 讲 · 图的存储结构'
  },
  {
    id: 105,
    type: '单选题',
    difficulty: '适中',
    topic: '排序',
    stem: '下列排序算法中，在最坏情况下时间复杂度仍为 O(n log n) 的是？',
    options: ['快速排序', '冒泡排序', '归并排序', '直接插入排序'],
    answer: 2,
    explanation: '归并排序在最好、平均和最坏情况下均为 O(n log n)。快速排序最坏情况下会退化到 O(n²)。',
    source: '第 12 讲 · 内部排序'
  },
  {
    id: 106,
    type: '单选题',
    difficulty: '基础',
    topic: '排序',
    stem: '直接插入排序在待排序序列已经有序时，其时间复杂度为？',
    options: ['O(1)', 'O(log n)', 'O(n)', 'O(n²)'],
    answer: 2,
    explanation: '序列已有序时，每个元素只需与前一个元素比较一次，不发生移动，因此时间复杂度为 O(n)。',
    source: '第 11 讲 · 插入排序'
  },
  {
    id: 107,
    type: '应用题',
    difficulty: '进阶',
    topic: '二叉树',
    stem: '已知一棵二叉树的前序序列为 ABDECF，中序序列为 DBEAFC，则其根节点的右子树根节点是？',
    options: ['B', 'C', 'D', 'F'],
    answer: 1,
    explanation: '前序序列首元素 A 为根。A 在中序序列中把左右子树分为 DBE 和 FC，右子树前序部分为 CF，所以右子树根节点为 C。',
    source: '第 7 讲 · 遍历序列还原'
  },
  {
    id: 108,
    type: '单选题',
    difficulty: '适中',
    topic: '图',
    stem: '对无权图求单源最短路径时，优先选择哪一种遍历策略？',
    options: ['深度优先搜索', '广度优先搜索', '拓扑排序', '关键路径算法'],
    answer: 1,
    explanation: '无权图中每条边代价相同，广度优先搜索按路径长度逐层扩展，首次到达顶点时即可得到最短路径。',
    source: '第 10 讲 · 图的遍历'
  }
];

@Component
export struct PracticePage {
  @State selectedMode: string = '智能组卷';
  @State selectedTopic: string = '综合';
  @State selectedDifficulty: string = '综合';
  @State requirementText: string = '';
  @State questionBank: PracticeQuestion[] = QUESTION_BANK;
  @State questionIndexes: number[] = [0, 1, 2, 3, 4];
  @State currentIndex: number = 0;
  @State selectedAnswers: number[] = [-1, -1, -1, -1, -1];
  @State submittedFlags: boolean[] = [false, false, false, false, false];
  @State generating: boolean = false;
  @State pageReady: boolean = false;
  @State pressedChoice: number = -1;
  private introTimer: number = -1;

  aboutToAppear(): void {
    this.pageReady = false;
    this.introTimer = setTimeout(() => {
      this.pageReady = true;
      this.introTimer = -1;
    }, 24);
  }

  aboutToDisappear(): void {
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

  private topicQuestionCount(topic: string): number {
    let count: number = 0;
    for (let i = 0; i < this.questionBank.length; i++) {
      if (this.questionBank[i].topic === topic) {
        count++;
      }
    }
    return count;
  }

  private async generateQuestions(): Promise<void> {
    if (this.generating) {
      return;
    }
    this.generating = true;
    const body: GeneratePracticeBody = {
      class_course_id: GlobalState.courseId(),
      user_id: GlobalState.userId(),
      count: 5,
      mode: this.selectedMode,
      topic: this.selectedTopic,
      difficulty: this.selectedDifficulty,
      requirements: this.requirementText.trim()
    };
    try {
      const response: PracticeGenerationResponse = JSON.parse(
        await Api.postLong('/practice/generate', body)) as PracticeGenerationResponse;
      if (response.questions.length === 0) {
        throw new Error('后端未返回有效题目');
      }
      this.questionBank = response.questions;
      const next: number[] = [];
      for (let i = 0; i < response.questions.length; i++) {
        next.push(i);
      }
      this.currentIndex = 0;
      this.questionIndexes = next;
      this.selectedAnswers = this.blankNumbers(next.length, -1);
      this.submittedFlags = this.blankBooleans(next.length);
      promptAction.showToast({ message: `已生成 ${next.length} 道${this.selectedTopic}练习题` });
    } catch (e) {
      promptAction.showToast({ message: `生成题目失败：${(e as Error).message}`, duration: 3500 });
    } finally {
      this.generating = false;
    }
  }

  private currentSelectedAnswer(): number {
    return this.selectedAnswers[this.currentIndex] ?? -1;
  }

  private currentSubmitted(): boolean {
    return this.submittedFlags[this.currentIndex] ?? false;
  }

  private chooseAnswer(index: number): void {
    if (this.currentSubmitted()) {
      return;
    }
    const next: number[] = this.selectedAnswers.slice();
    next[this.currentIndex] = index;
    this.selectedAnswers = next;
  }

  private submitAnswer(): void {
    if (this.currentSelectedAnswer() < 0 || this.currentSubmitted()) {
      return;
    }
    const next: boolean[] = this.submittedFlags.slice();
    next[this.currentIndex] = true;
    this.submittedFlags = next;
  }

  private answeredCount(): number {
    let count: number = 0;
    for (let i = 0; i < this.submittedFlags.length; i++) {
      if (this.submittedFlags[i]) {
        count++;
      }
    }
    return count;
  }

  private correctCount(): number {
    let count: number = 0;
    const limit: number = Math.min(
      this.submittedFlags.length,
      Math.min(this.selectedAnswers.length, this.questionIndexes.length)
    );
    for (let i = 0; i < limit; i++) {
      if (this.submittedFlags[i] &&
        this.selectedAnswers[i] === this.questionBank[this.questionIndexes[i]].answer) {
        count++;
      }
    }
    return count;
  }

  private accuracyText(): string {
    const answered: number = this.answeredCount();
    return answered === 0 ? '0%' : `${Math.round(this.correctCount() * 100 / answered)}%`;
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
    Button(label)
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
      Text(label === '综合' ? 'ALL' : `${this.topicQuestionCount(label)}`)
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
  statValue(value: string, label: string, color: string) {
    Column({ space: 3 }) {
      Text(value)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(label)
        .fontSize(10)
        .fontColor(AppTheme.TEXT_TERTIARY)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
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
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(28)
        .linearGradient({
          angle: 118,
          colors: [
            ['#FFFFFF', 0],
            ['#F2FFFA', 0.54],
            ['#EEF4FF', 1]
          ]
        })
      Column()
        .width(240)
        .height(92)
        .borderRadius(28)
        .rotate({ angle: -8 })
        .backgroundColor('rgba(5,206,145,0.10)')
        .position({ x: -52, y: -40 })
      Column()
        .width(210)
        .height(88)
        .borderRadius(24)
        .rotate({ angle: 9 })
        .backgroundColor('rgba(63,125,255,0.10)')
        .position({ x: 530, y: 44 })
      Row() {
        Column({ space: 5 }) {
          Row({ space: 8 }) {
            Text('PRACTICE LAB')
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.INK)
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
          Text(this.generating ? 'AI 正在组题' : '题组已就绪')
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
    .borderRadius(28)
    .border({ width: 1.2, color: 'rgba(255,255,255,0.92)' })
    .shadow({ radius: 26, color: PRACTICE_SHADOW, offsetX: 0, offsetY: 10 })
  }

  @Builder
  leftPanel() {
    Column() {
      Column({ space: 5 }) {
        Text('刷题计划')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.INK)
        Text(this.courseName())
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row() {
        this.statValue(`${this.answeredCount()}`, '已答', PRACTICE_BLUE)
        this.statValue(`${this.correctCount()}`, '正确', AppTheme.SUCCESS)
        this.statValue(this.accuracyText(), '正确率', PRACTICE_VIOLET)
      }
      .width('100%')
      .margin({ top: 22, bottom: 22 })

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
      Column({ space: 2 }) {
        ForEach(PRACTICE_TOPICS, (topic: string) => {
          this.topicButton(topic)
        }, (topic: string) => topic)
      }
      .width('100%')

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

      Blank()

      Button(this.generating ? '正在生成…' : '✦  AI 出题')
        .fontSize(AppTheme.FONT_BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width('100%')
        .height(46)
        .borderRadius(23)
        .backgroundColor(this.generating ? AppTheme.TEXT_TERTIARY : AppTheme.PRIMARY)
        .enabled(!this.generating)
        .onClick(() => {
          this.generateQuestions();
        })
    }
    .width(244)
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
      Text(option)
        .fontSize(AppTheme.FONT_BODY)
        .fontWeight(index === this.currentSelectedAnswer() ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.optionTextColor(index))
        .layoutWeight(1)
        .maxLines(3)
    }
    .width('100%')
    .height(58)
    .padding({ left: 14, right: 16 })
    .borderRadius(16)
    .backgroundColor(this.optionBackground(index))
    .border({ width: 1.2, color: this.optionBorderColor(index) })
    .translate({ x: 0, y: this.pressedChoice === index ? 2 : 0 })
    .scale({ x: this.pressedChoice === index ? 0.992 : 1, y: this.pressedChoice === index ? 0.992 : 1 })
    .animation({ duration: 100, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedChoice = index;
      } else if (event.type === TouchType.Up) {
        this.pressedChoice = -1;
      }
    })
    .onClick(() => {
      this.pressedChoice = -1;
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
      Text(this.currentQuestion().explanation)
        .fontSize(AppTheme.FONT_BODY)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .lineHeight(23)
        .width('100%')
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
        Text(this.currentQuestion().source)
          .fontSize(10)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
      .width('100%')

      Text(this.currentQuestion().stem)
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.INK)
        .lineHeight(31)
        .width('100%')
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
        Button('‹')
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
        Button('›')
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
        Button(this.currentSubmitted() ? '已提交' : '提交答案')
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
    .layoutWeight(1)
    .padding({ left: 28, right: 28, top: 24, bottom: 22 })
    .borderRadius(28)
    .backgroundColor('rgba(255,255,255,0.94)')
    .border({ width: 1.2, color: 'rgba(255,255,255,0.98)' })
    .shadow({ radius: 26, color: PRACTICE_SHADOW, offsetX: 0, offsetY: 10 })
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
        Text(`${this.currentIndex + 1}`)
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
      Row({ space: 8 }) {
        ForEach(this.questionIndexes, (bankIndex: number, index: number) => {
          this.questionNavItem(index)
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
        Row({ space: 6 }) {
          Column().width(10).height(10).borderRadius(5).backgroundColor(AppTheme.PRIMARY)
          Text('课程提纲').fontSize(11).fontColor(AppTheme.TEXT_SECONDARY)
        }
        Row({ space: 6 }) {
          Column().width(10).height(10).borderRadius(5).backgroundColor(PRACTICE_BLUE)
          Text('课堂重点').fontSize(11).fontColor(AppTheme.TEXT_SECONDARY)
        }
        Row({ space: 6 }) {
          Column().width(10).height(10).borderRadius(5).backgroundColor(PRACTICE_AMBER)
          Text('个人错题').fontSize(11).fontColor(AppTheme.TEXT_SECONDARY)
        }
      }
      .width('100%')
      .padding({ top: 18, bottom: 18 })
      .margin({ top: 28 })
      .border({ width: { top: 1, bottom: 1 }, color: AppTheme.DIVIDER })

      Blank()

      Row({ space: 8 }) {
        Column().width(8).height(8).borderRadius(4).backgroundColor(PRACTICE_CYAN)
        Text(this.generating ? 'AI 正在组织题目' : '题组已就绪')
          .fontSize(11)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
      .width('100%')
    }
    .width(264)
    .height('100%')
    .padding({ left: 22, right: 22, top: 26, bottom: 24 })
    .borderRadius(28)
    .backgroundColor('rgba(255,255,255,0.92)')
    .border({ width: 1.2, color: 'rgba(255,255,255,0.96)' })
    .shadow({ radius: 24, color: PRACTICE_SHADOW, offsetX: 0, offsetY: 10 })
  }

  build() {
    Stack() {
      this.pageAtmosphere()
      Row({ space: AppTheme.SPACE_L }) {
        this.leftPanel()

        Column({ space: AppTheme.SPACE_L }) {
          this.practiceHeader()
          this.questionPanel()
        }
        .layoutWeight(1)
        .height('100%')
        .opacity(this.pageReady ? 1 : 0)
        .translate({ x: 0, y: this.pageReady ? 0 : 16 })
        .animation({ duration: 320, curve: Curve.EaseOut })

        this.rightPanel()
      }
      .width('100%')
      .height('100%')
      .padding({ left: AppTheme.SPACE_XXL, right: AppTheme.SPACE_XXL, top: 28, bottom: AppTheme.SPACE_XXL })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PRACTICE_BG)
  }
}
