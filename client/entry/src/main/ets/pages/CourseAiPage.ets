import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import {
  ChatMessageInfo,
  ChatSessionInfo,
  ClassroomAnalytics,
  KB_FALLBACK_WARNING,
  KeywordInsight,
  UiChatMessage
} from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

const AI_BG: string = '#F2F7F6';
const AI_PANEL: string = '#FFFFFF';
const AI_SOFT: string = '#F5FFFB';
const AI_BLUE: string = '#3F7DFF';
const AI_CYAN: string = '#12BFE8';
const AI_VIOLET: string = '#7A63F3';
const AI_AMBER: string = '#FFB84D';
const AI_GLASS: string = 'rgba(255,255,255,0.90)';
const AI_BORDER: string = 'rgba(255,255,255,0.92)';

@Component
export struct CourseAiPage {
  @State chatSessions: ChatSessionInfo[] = [];
  @State selectedChatIndex: number = -1;
  @State messages: UiChatMessage[] = [];
  @State inputText: string = '';
  @State asking: boolean = false;
  @State analytics: ClassroomAnalytics | null = null;
  @State analyticsLoading: boolean = false;
  @State pageReady: boolean = false;
  @State pulse: boolean = false;
  private msgScroller: Scroller = new Scroller();
  private introTimer: number = -1;
  private pulseTimer: number = -1;
  private analyticsTimer: number = -1;

  aboutToAppear(): void {
    this.loadChatSessions();
    this.pageReady = false;
    this.introTimer = setTimeout(() => {
      this.pageReady = true;
      this.introTimer = -1;
    }, 24);
    if (this.pulseTimer < 0) {
      this.pulseTimer = setInterval(() => {
        this.pulse = !this.pulse;
      }, 1500);
    }
    if (GlobalState.isTeacher()) {
      this.loadAnalytics();
      if (this.analyticsTimer < 0) {
        this.analyticsTimer = setInterval(() => {
          this.loadAnalytics();
        }, 3000);
      }
    }
  }

  aboutToDisappear(): void {
    if (this.introTimer >= 0) {
      clearTimeout(this.introTimer);
      this.introTimer = -1;
    }
    if (this.pulseTimer >= 0) {
      clearInterval(this.pulseTimer);
      this.pulseTimer = -1;
    }
    if (this.analyticsTimer >= 0) {
      clearInterval(this.analyticsTimer);
      this.analyticsTimer = -1;
    }
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private async loadAnalytics(): Promise<void> {
    if (!GlobalState.isTeacher() || GlobalState.courseId() < 0 || this.analyticsLoading) {
      return;
    }
    this.analyticsLoading = true;
    try {
      const raw: string = await Api.get(
        `/analytics/classroom?class_course_id=${GlobalState.courseId()}&user_id=${GlobalState.userId()}&limit=8`);
      this.analytics = JSON.parse(raw) as ClassroomAnalytics;
    } catch (e) {
      if (this.analytics === null) {
        this.toast(`加载课堂洞察失败：${(e as Error).message}`);
      }
    } finally {
      this.analyticsLoading = false;
    }
  }

  private topKeywords(): KeywordInsight[] {
    return this.analytics === null ? [] : this.analytics.top_keywords;
  }

  private hotZones(): KeywordInsight[] {
    return this.analytics === null ? [] : this.analytics.hot_zones;
  }

  private topInsight(): KeywordInsight | null {
    const items: KeywordInsight[] = this.topKeywords();
    return items.length === 0 ? null : items[0];
  }

  private missedRatio(): string {
    if (this.analytics === null || this.analytics.total_questions <= 0) {
      return '0%';
    }
    return `${Math.round(this.analytics.missed_count * 100 / this.analytics.total_questions)}%`;
  }

  private updatedAtText(): string {
    if (this.analytics === null || this.analytics.updated_at.length < 19) {
      return this.analyticsLoading ? '刷新中' : '待刷新';
    }
    return this.analytics.updated_at.substring(11, 19);
  }

  private heatWidth(item: KeywordInsight): string {
    const heat: number = Math.max(8, Math.min(100, item.heat));
    return `${heat}%`;
  }

  private levelColor(level: string): string {
    if (level === '高') {
      return AI_AMBER;
    }
    if (level === '中') {
      return AI_BLUE;
    }
    return AppTheme.PRIMARY;
  }

  private topExamples(): string[] {
    const top: KeywordInsight | null = this.topInsight();
    return top === null ? [] : top.examples;
  }

  private topKeywordText(): string {
    const top: KeywordInsight | null = this.topInsight();
    return top === null ? '暂无热词' : top.keyword;
  }

  private topKeywordCountText(): string {
    const top: KeywordInsight | null = this.topInsight();
    return top === null ? '0' : `${top.count}`;
  }

  private topKeywordMissedText(): string {
    const top: KeywordInsight | null = this.topInsight();
    return top === null ? '0' : `${top.missed_count}`;
  }

  private totalQuestionsText(): string {
    return this.analytics === null ? '0' : `${this.analytics.total_questions}`;
  }

  private missedCountText(): string {
    return this.analytics === null ? '0' : `${this.analytics.missed_count}`;
  }

  private async loadChatSessions(): Promise<void> {
    try {
      this.chatSessions = JSON.parse(await Api.get(
        `/chat/sessions?class_course_id=${GlobalState.courseId()}&user_id=${GlobalState.userId()}`)) as ChatSessionInfo[];
      if (this.chatSessions.length > 0 && this.selectedChatIndex < 0) {
        this.selectChat(0);
      }
    } catch (e) {
      this.chatSessions = [];
      this.toast(`加载 AI 会话失败：${(e as Error).message}`);
    }
  }

  private async selectChat(index: number): Promise<void> {
    this.selectedChatIndex = index;
    const cs: ChatSessionInfo = this.chatSessions[index];
    try {
      const list: ChatMessageInfo[] = JSON.parse(
        await Api.get(`/chat/sessions/${cs.id}/messages`)) as ChatMessageInfo[];
      this.messages = list.map((m: ChatMessageInfo): UiChatMessage => {
        let sources: string[] = [];
        if (m.sources !== '') {
          try {
            sources = JSON.parse(m.sources) as string[];
          } catch (e) {
            sources = [];
          }
        }
        let content: string = m.content;
        let warning: string = '';
        if (m.role === 'assistant' && content.startsWith(KB_FALLBACK_WARNING)) {
          warning = KB_FALLBACK_WARNING;
          content = content.substring(KB_FALLBACK_WARNING.length).trim();
        }
        const ui: UiChatMessage = {
          role: m.role, content: content, sources: sources, warning: warning, streaming: false
        };
        return ui;
      });
    } catch (e) {
      this.messages = [];
      this.toast(`加载会话失败：${(e as Error).message}`);
    }
  }

  private newSession(): void {
    this.selectedChatIndex = -1;
    this.messages = [];
    this.inputText = '';
  }

  private async deleteChatSession(index: number): Promise<void> {
    if (index < 0 || index >= this.chatSessions.length) {
      return;
    }
    if (this.asking && this.selectedChatIndex === index) {
      this.toast('当前会话正在生成回答，请稍后删除');
      return;
    }
    const cs: ChatSessionInfo = this.chatSessions[index];
    const result = await promptAction.showDialog({
      title: '删除对话',
      message: `确定删除“${cs.title}”及其全部消息吗？`,
      buttons: [
        { text: '取消', color: AppTheme.TEXT_SECONDARY },
        { text: '删除', color: AppTheme.DANGER }
      ]
    });
    if (result.index !== 1) {
      return;
    }
    try {
      await Api.remove(`/chat/sessions/${cs.id}?user_id=${GlobalState.userId()}`);
      const wasSelected: boolean = this.selectedChatIndex === index;
      this.chatSessions = this.chatSessions.filter((item: ChatSessionInfo) => item.id !== cs.id);
      if (wasSelected) {
        this.selectedChatIndex = -1;
        this.messages = [];
        if (this.chatSessions.length > 0) {
          await this.selectChat(Math.min(index, this.chatSessions.length - 1));
        }
      } else if (this.selectedChatIndex > index) {
        this.selectedChatIndex -= 1;
      }
      if (GlobalState.isTeacher()) {
        this.loadAnalytics();
      }
      this.toast('对话已删除');
    } catch (e) {
      this.toast(`删除对话失败：${(e as Error).message}`);
    }
  }

  private replaceLastMessage(m: UiChatMessage): void {
    this.messages.splice(this.messages.length - 1, 1, m);
  }

  private buildMemory(): string {
    if (this.messages.length === 0) {
      return '';
    }
    const start: number = Math.max(0, this.messages.length - 8);
    const parts: string[] = ['[对话记忆：仅用于理解上下文、代词和学习偏好，课程事实仍以知识库片段为准]'];
    for (let i = start; i < this.messages.length; i++) {
      const m: UiChatMessage = this.messages[i];
      const role: string = m.role === 'user' ? '学生' : 'AI';
      parts.push(`${role}：${m.content}`);
    }
    return parts.join('\n');
  }

  private async ensureChatSession(firstQuestion: string): Promise<number> {
    if (this.selectedChatIndex >= 0 && this.selectedChatIndex < this.chatSessions.length) {
      return this.chatSessions[this.selectedChatIndex].id;
    }
    interface CreateChat {
      class_course_id: number;
      user_id: number;
      title: string;
    }

    const body: CreateChat = {
      class_course_id: GlobalState.courseId(),
      user_id: GlobalState.userId(),
      title: firstQuestion.length > 14 ? firstQuestion.substring(0, 14) + '…' : firstQuestion
    };
    const cs: ChatSessionInfo = JSON.parse(await Api.post('/chat/sessions', body)) as ChatSessionInfo;
    this.chatSessions = [cs].concat(this.chatSessions);
    this.selectedChatIndex = 0;
    return cs.id;
  }

  private async send(): Promise<void> {
    const q: string = this.inputText.trim();
    if (q === '' || this.asking) {
      return;
    }
    this.inputText = '';
    this.asking = true;
    const memory: string = this.buildMemory();
    let chatId: number = -1;
    try {
      chatId = await this.ensureChatSession(q);
    } catch (e) {
      this.asking = false;
      this.toast(`创建会话失败：${(e as Error).message}`);
      return;
    }

    const userMsg: UiChatMessage = { role: 'user', content: q, sources: [], warning: '', streaming: false };
    const holder: UiChatMessage = { role: 'assistant', content: '', sources: [], warning: '', streaming: true };
    this.messages.push(userMsg);
    this.messages.push(holder);
    this.msgScroller.scrollEdge(Edge.Bottom);

    Api.streamAsk(chatId, q, memory, {
      onSources: (sources: string[]) => {
        const last: UiChatMessage = this.messages[this.messages.length - 1];
        const next: UiChatMessage =
          { role: 'assistant', content: last.content, sources: sources, warning: last.warning, streaming: true };
        this.replaceLastMessage(next);
      },
      onWarning: (msg: string) => {
        const last: UiChatMessage = this.messages[this.messages.length - 1];
        const next: UiChatMessage = {
          role: 'assistant', content: last.content, sources: last.sources, warning: msg, streaming: true
        };
        this.replaceLastMessage(next);
        promptAction.showToast({ message: msg, duration: 3000 });
      },
      onDelta: (delta: string) => {
        const last: UiChatMessage = this.messages[this.messages.length - 1];
        const next: UiChatMessage =
          {
            role: 'assistant', content: last.content + delta,
            sources: last.sources, warning: last.warning, streaming: true
          };
        this.replaceLastMessage(next);
        this.msgScroller.scrollEdge(Edge.Bottom);
      },
      onDone: () => {
        const last: UiChatMessage = this.messages[this.messages.length - 1];
        const next: UiChatMessage =
          {
            role: 'assistant', content: last.content,
            sources: last.sources, warning: last.warning, streaming: false
          };
        this.replaceLastMessage(next);
        this.asking = false;
      },
      onError: (msg: string) => {
        const last: UiChatMessage = this.messages[this.messages.length - 1];
        const next: UiChatMessage = {
          role: 'assistant',
          content: last.content === '' ? `（请求失败：${msg}）` : last.content,
          sources: last.sources,
          warning: last.warning,
          streaming: false
        };
        this.replaceLastMessage(next);
        this.asking = false;
      }
    });
  }

  @Builder
  pageHeader() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(32)
        .linearGradient({
          angle: 118,
          colors: [
            [AI_PANEL, 0],
            [AI_SOFT, 0.58],
            ['#EEF3FF', 1]
          ]
        })
      Column()
        .width(460)
        .height(210)
        .borderRadius(44)
        .rotate({ angle: -11 })
        .linearGradient({
          angle: 86,
          colors: [
            ['rgba(63,125,255,0.24)', 0],
            ['rgba(122,99,243,0.13)', 0.62],
            ['rgba(255,255,255,0.02)', 1]
          ]
        })
        .position({ x: 640, y: -70 })
        .translate({ x: this.pulse ? -10 : 0, y: this.pulse ? 6 : 0 })
        .animation({ duration: 1200, curve: Curve.EaseOut })
      Row() {
        Column({ space: AppTheme.SPACE_M }) {
          Row({ space: 8 }) {
            Text('COURSE AI')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor('#121818')
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(999)
              .backgroundColor(AI_CYAN)
            Text('仅依据本课程知识库')
              .fontSize(11)
              .fontColor('rgba(18,24,24,0.58)')
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(999)
              .backgroundColor('rgba(18,24,24,0.06)')
          }
          Text('AI')
            .fontSize(48)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK)
          Text('把课堂提纲、共享笔记和提问上下文编织成一次更可靠的课程问答。')
            .fontSize(AppTheme.FONT_BODY)
            .fontColor('rgba(18,24,24,0.56)')
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        this.knowledgeGlyph()
      }
      .width('100%')
      .height('100%')
      .padding({ left: 34, right: 32 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(190)
    .clip(true)
    .borderRadius(32)
    .border({ width: 1.2, color: AI_BORDER })
    .shadow({ radius: 30, color: 'rgba(31,62,68,0.12)', offsetX: 0, offsetY: 14 })
  }

  @Builder
  knowledgeGlyph() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(156)
        .height(156)
        .borderRadius(78)
        .border({ width: 1.4, color: 'rgba(18,24,24,0.12)' })
      Column()
        .width(86)
        .height(2)
        .borderRadius(1)
        .rotate({ angle: 28 })
        .backgroundColor('rgba(18,191,232,0.42)')
        .position({ x: 48, y: 74 })
      Column()
        .width(70)
        .height(2)
        .borderRadius(1)
        .rotate({ angle: -35 })
        .backgroundColor('rgba(5,206,145,0.40)')
        .position({ x: 86, y: 78 })
      Column()
        .width(58)
        .height(2)
        .borderRadius(1)
        .rotate({ angle: 85 })
        .backgroundColor('rgba(255,184,77,0.38)')
        .position({ x: 87, y: 104 })
      this.glyphNode('问', AI_BLUE, 34, 56, 48)
      this.glyphNode('AI', AI_VIOLET, 92, 78, 58)
      this.glyphNode('课', AppTheme.PRIMARY, 148, 40, 42)
      this.glyphNode('记', AI_AMBER, 98, 144, 38)
    }
    .width(210)
    .height(190)
    .scale({ x: this.pulse ? 1.025 : 1, y: this.pulse ? 1.025 : 1 })
    .animation({ duration: 1200, curve: Curve.EaseOut })
  }

  @Builder
  glyphNode(label: string, color: string, x: number, y: number, size: number) {
    Text(label)
      .fontSize(size > 48 ? 16 : 13)
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .width(size)
      .height(size)
      .textAlign(TextAlign.Center)
      .borderRadius(size / 2)
      .backgroundColor(color)
      .border({ width: 1.2, color: 'rgba(255,255,255,0.78)' })
      .shadow({ radius: 18, color: color, offsetX: 0, offsetY: 8 })
      .position({ x: x, y: y })
  }

  @Builder
  historyPane() {
    Column({ space: AppTheme.SPACE_M }) {
      Row() {
        Text('历史会话')
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.INK)
        Blank()
        Text('+')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#121818')
          .width(34)
          .height(34)
          .textAlign(TextAlign.Center)
          .borderRadius(17)
          .backgroundColor(AppTheme.PRIMARY)
          .shadow({ radius: 14, color: 'rgba(5,206,145,0.26)', offsetX: 0, offsetY: 6 })
          .onClick(() => {
            this.newSession();
          })
      }
      .width('100%')

      Text('课程问答会自动保留最近上下文')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .width('100%')

      if (this.chatSessions.length === 0) {
        Column({ space: AppTheme.SPACE_S }) {
          Text('暂无会话')
            .fontSize(AppTheme.FONT_BODY)
            .fontColor(AppTheme.TEXT_SECONDARY)
          Text('提问后会在这里生成记录')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: AppTheme.SPACE_S }) {
          ForEach(this.chatSessions, (cs: ChatSessionInfo, index: number) => {
            ListItem() {
              Row({ space: 10 }) {
                Column()
                  .width(8)
                  .height(8)
                  .borderRadius(4)
                  .backgroundColor(this.selectedChatIndex === index ? AppTheme.PRIMARY : 'rgba(18,24,24,0.18)')
                Text(cs.title)
                  .fontSize(AppTheme.FONT_BODY)
                  .fontColor(this.selectedChatIndex === index ? AppTheme.INK : AppTheme.TEXT_SECONDARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                  .onClick(() => {
                    this.selectChat(index);
                  })
                Text('×')
                  .fontSize(18)
                  .fontColor(AppTheme.TEXT_TERTIARY)
                  .width(28)
                  .height(28)
                  .textAlign(TextAlign.Center)
                  .borderRadius(14)
                  .backgroundColor('rgba(255,92,92,0.08)')
                  .onClick(() => {
                    this.deleteChatSession(index);
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 11, bottom: 11 })
              .borderRadius(18)
              .backgroundColor(this.selectedChatIndex === index ? AppTheme.PRIMARY_LIGHT : 'transparent')
              .border({
                width: 1,
                color: this.selectedChatIndex === index ? 'rgba(5,206,145,0.22)' : 'rgba(18,24,24,0.06)'
              })
            }
          }, (cs: ChatSessionInfo) => `${cs.id}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width(278)
    .height('100%')
    .padding(AppTheme.SPACE_L)
    .borderRadius(30)
    .linearGradient({
      angle: 140,
      colors: [
        ['#FFFFFF', 0],
        ['#F6FFFB', 0.62],
        ['#EEF3FF', 1]
      ]
    })
    .border({ width: 1.2, color: AI_BORDER })
    .shadow({ radius: 26, color: 'rgba(31,62,68,0.12)', offsetX: 0, offsetY: 12 })
  }

  @Builder
  insightMetric(label: string, value: string, sub: string, color: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.INK)
      Text(label)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
      Text(sub)
        .fontSize(10)
        .fontColor(color)
    }
    .layoutWeight(1)
    .height(92)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .borderRadius(22)
    .backgroundColor('rgba(255,255,255,0.78)')
    .border({ width: 1.1, color: AI_BORDER })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  teacherSpotlightPanel() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(30)
        .linearGradient({
          angle: 118,
          colors: [
            ['#121818', 0],
            ['#1E3A36', 0.58],
            ['#243F55', 1]
          ]
        })
      Column()
        .width(260)
        .height(180)
        .borderRadius(46)
        .rotate({ angle: -12 })
        .backgroundColor('rgba(5,206,145,0.18)')
        .position({ x: -70, y: -34 })
        .translate({ x: this.pulse ? 8 : 0, y: this.pulse ? 0 : 6 })
        .animation({ duration: 1200, curve: Curve.EaseOut })
      Column()
        .width(320)
        .height(150)
        .borderRadius(42)
        .rotate({ angle: 9 })
        .backgroundColor('rgba(63,125,255,0.16)')
        .position({ x: 540, y: -36 })
        .translate({ x: this.pulse ? -10 : 0, y: this.pulse ? 6 : 0 })
        .animation({ duration: 1200, curve: Curve.EaseOut })
      Row() {
        Column({ space: 10 }) {
          Text('当前疑问焦点')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.PRIMARY)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(999)
            .backgroundColor('rgba(5,206,145,0.14)')
          Text(this.topKeywordText())
            .fontSize(44)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('系统正在汇总学生在课程 AI 中提出的问题，帮助老师快速发现课堂卡点。')
            .fontSize(AppTheme.FONT_BODY)
            .fontColor('rgba(255,255,255,0.62)')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Row({ space: AppTheme.SPACE_M }) {
          this.spotlightNumber('提问', this.topKeywordCountText(), AppTheme.PRIMARY)
          this.spotlightNumber('未命中', this.topKeywordMissedText(), AI_AMBER)
          this.spotlightNumber('占比', this.missedRatio(), AI_CYAN)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 30, right: 28, top: 24, bottom: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(190)
    .clip(true)
    .borderRadius(30)
    .border({ width: 1.2, color: 'rgba(255,255,255,0.18)' })
    .shadow({ radius: 34, color: 'rgba(18,24,24,0.20)', offsetX: 0, offsetY: 16 })
  }

  @Builder
  spotlightNumber(label: string, value: string, color: string) {
    Column({ space: 5 }) {
      Text(value)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
      Text(label)
        .fontSize(11)
        .fontColor('rgba(255,255,255,0.62)')
    }
    .width(94)
    .height(86)
    .borderRadius(22)
    .backgroundColor('rgba(255,255,255,0.10)')
    .border({ width: 1, color: color })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  keywordRow(item: KeywordInsight, index: number) {
    Row({ space: 10 }) {
      Text(`${index + 1}`)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width(24)
        .height(24)
        .textAlign(TextAlign.Center)
        .borderRadius(12)
        .backgroundColor(index === 0 ? AI_AMBER : (index === 1 ? AI_BLUE : AppTheme.PRIMARY))
      Column({ space: 5 }) {
        Row() {
          Text(item.keyword)
            .fontSize(AppTheme.FONT_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.INK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(`${item.count} 次`)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .width('100%')
        Stack({ alignContent: Alignment.TopStart }) {
          Column()
            .width('100%')
            .height(6)
            .borderRadius(3)
            .backgroundColor('rgba(18,24,24,0.06)')
          Column()
            .width(this.heatWidth(item))
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.levelColor(item.level))
        }
        .width('100%')
        .height(6)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(18)
    .backgroundColor('rgba(255,255,255,0.62)')
    .border({ width: 1, color: 'rgba(255,255,255,0.72)' })
  }

  @Builder
  topExamplePanel() {
    Column({ space: AppTheme.SPACE_S }) {
      Row() {
        Text('被问最多关键词典例')
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.INK)
        Blank()
        if (this.topExamples().length > 0) {
          Text(this.topKeywordText())
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AI_BLUE)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(999)
            .backgroundColor(AppTheme.tagBg(AI_BLUE))
        }
      }
      .width('100%')

      if (this.topExamples().length === 0) {
        Text('暂无学生问题典例')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .width('100%')
          .padding({ top: 10, bottom: 10 })
      } else {
        ForEach(this.topExamples(), (question: string, index: number) => {
          Text(`${index + 1}. ${question}`)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_SECONDARY)
            .lineHeight(18)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }, (question: string, index: number) => `${index}_${question}`)
      }
    }
    .width('100%')
    .padding(AppTheme.SPACE_M)
    .borderRadius(24)
    .backgroundColor('rgba(255,255,255,0.72)')
    .border({ width: 1.1, color: AI_BORDER })
  }

  @Builder
  heatZoneRow(item: KeywordInsight) {
    Row({ space: 10 }) {
      Column()
        .width(10)
        .height(10)
        .borderRadius(5)
        .backgroundColor(this.levelColor(item.level))
      Text(item.keyword)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(`${item.level}热`)
        .fontSize(10)
        .fontColor(this.levelColor(item.level))
      Text(`未命中 ${item.missed_count}`)
        .fontSize(10)
        .fontColor(AppTheme.TEXT_TERTIARY)
    }
    .width('100%')
  }

  @Builder
  teacherInsightPane() {
    Column({ space: AppTheme.SPACE_M }) {
      Row() {
        Column({ space: 3 }) {
          Text('课堂疑问洞察')
            .fontSize(AppTheme.FONT_BODY)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK)
          Text(`轮询更新 · ${this.updatedAtText()}`)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Column()
          .width(10)
          .height(10)
          .borderRadius(5)
          .backgroundColor(this.analyticsLoading ? AI_AMBER : AppTheme.PRIMARY)
      }
      .width('100%')

      Row({ space: AppTheme.SPACE_S }) {
        this.insightMetric('累计学生提问', this.totalQuestionsText(), 'Question Log', AppTheme.PRIMARY)
        this.insightMetric('知识库未命中', this.missedCountText(), this.missedRatio(), AI_AMBER)
      }
      .width('100%')

      this.teacherSpotlightPanel()

      Scroll() {
        Column({ space: AppTheme.SPACE_M }) {
          Column({ space: AppTheme.SPACE_S }) {
            Text('实时高频问题关键词')
              .fontSize(AppTheme.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.INK)
              .width('100%')
            if (this.topKeywords().length === 0) {
              Text('学生开始提问后，这里会出现热词排行')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_TERTIARY)
                .width('100%')
                .padding({ top: 12, bottom: 12 })
            } else {
              ForEach(this.topKeywords(), (item: KeywordInsight, index: number) => {
                this.keywordRow(item, index)
              }, (item: KeywordInsight) => `${item.keyword}`)
            }
          }
          .width('100%')

          this.topExamplePanel()

          Column({ space: AppTheme.SPACE_S }) {
            Text('学生疑惑热区')
              .fontSize(AppTheme.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.INK)
              .width('100%')
            if (this.hotZones().length === 0) {
              Text('暂无热区')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_TERTIARY)
            } else {
              ForEach(this.hotZones(), (item: KeywordInsight) => {
                this.heatZoneRow(item)
              }, (item: KeywordInsight) => `${item.keyword}_hot`)
            }
          }
          .width('100%')
          .padding(AppTheme.SPACE_M)
          .borderRadius(24)
          .backgroundColor('rgba(255,255,255,0.70)')
          .border({ width: 1.1, color: AI_BORDER })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .layoutWeight(1)
    .height('100%')
    .padding(AppTheme.SPACE_L)
    .borderRadius(30)
    .linearGradient({
      angle: 150,
      colors: [
        ['#FFFFFF', 0],
        ['#F8FFFC', 0.58],
        ['#EEF3FF', 1]
      ]
    })
    .border({ width: 1.2, color: AI_BORDER })
    .shadow({ radius: 26, color: 'rgba(31,62,68,0.12)', offsetX: 0, offsetY: 12 })
  }

  @Builder
  messageBubble(m: UiChatMessage) {
    Row() {
      if (m.role === 'user') {
        Blank()
      }
      Column({ space: AppTheme.SPACE_XS }) {
        Row({ space: 6 }) {
          Text(m.role === 'user' ? '我' : 'AI')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(m.role === 'user' ? AI_BLUE : AppTheme.PRIMARY)
          if (m.streaming) {
            Text('生成中')
              .fontSize(10)
              .fontColor(AI_VIOLET)
          }
        }
        if (m.warning !== '') {
          Row({ space: 10 }) {
            Text('!')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor('#9A5B00')
              .width(24)
              .height(24)
              .textAlign(TextAlign.Center)
              .borderRadius(12)
              .backgroundColor('#FFE3A3')
            Column({ space: 2 }) {
              Text('知识库提示')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontWeight(FontWeight.Bold)
                .fontColor('#8A5200')
              Text(m.warning)
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor('#9A640F')
                .lineHeight(18)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 9, bottom: 9 })
          .borderRadius(12)
          .backgroundColor('#FFF7E6')
          .border({ width: 1, color: '#F3CF85' })
        }
        Text(m.content + (m.streaming ? ' ▌' : ''))
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(m.role === 'user' ? '#FFFFFF' : AppTheme.TEXT_PRIMARY)
          .lineHeight(23)
        if (m.sources.length > 0) {
          Text(`来源：${m.sources.join('；')}`)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(m.role === 'user' ? 'rgba(255,255,255,0.72)' : AppTheme.TEXT_TERTIARY)
            .lineHeight(18)
        }
      }
      .constraintSize({ maxWidth: '76%' })
      .padding(AppTheme.SPACE_M)
      .borderRadius(22)
      .backgroundColor(m.role === 'user' ? AI_BLUE : AI_GLASS)
      .border({ width: 1.1, color: m.role === 'user' ? 'rgba(255,255,255,0.26)' : AI_BORDER })
      .shadow({
        radius: m.role === 'user' ? 18 : 22,
        color: m.role === 'user' ? 'rgba(63,125,255,0.18)' : 'rgba(31,62,68,0.10)',
        offsetX: 0,
        offsetY: 8
      })
      .alignItems(HorizontalAlign.Start)
      if (m.role !== 'user') {
        Blank()
      }
    }
    .width('100%')
  }

  @Builder
  emptyChatState() {
    Column({ space: AppTheme.SPACE_M }) {
      Stack({ alignContent: Alignment.Center }) {
        this.knowledgeGlyph()
      }
      .width(210)
      .height(190)
      .scale({ x: 0.82, y: 0.82 })
      Text('向课程 AI 提问')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.INK)
      Text('它会基于当前课程已入库的资料回答，并结合最近几轮对话理解你的学习上下文。')
        .fontSize(AppTheme.FONT_BODY)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: 520 })
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  chatPane() {
    Column({ space: AppTheme.SPACE_M }) {
      Row() {
        Column({ space: 4 }) {
          Text(this.selectedChatIndex >= 0 && this.selectedChatIndex < this.chatSessions.length ?
            this.chatSessions[this.selectedChatIndex].title : '新会话')
            .fontSize(AppTheme.FONT_SUBTITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('课程事实优先来自已发布课时和已入库笔记')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Text(this.asking ? '检索中' : '就绪')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(this.asking ? AI_VIOLET : AppTheme.PRIMARY)
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .borderRadius(999)
          .backgroundColor(AppTheme.tagBg(this.asking ? AI_VIOLET : AppTheme.PRIMARY))
      }
      .width('100%')

      if (this.messages.length === 0) {
        this.emptyChatState()
      } else {
        List({ space: AppTheme.SPACE_M, scroller: this.msgScroller }) {
          ForEach(this.messages, (m: UiChatMessage, index: number) => {
            ListItem() {
              this.messageBubble(m)
            }
          }, (m: UiChatMessage, index: number) => `${index}_${m.role}_${m.content.length}_${m.streaming}`)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
      }

      Row({ space: AppTheme.SPACE_S }) {
        TextInput({ text: this.inputText, placeholder: '输入你的问题…' })
          .layoutWeight(1)
          .fontSize(AppTheme.FONT_BODY)
          .height(46)
          .borderRadius(23)
          .backgroundColor('rgba(18,24,24,0.04)')
          .onChange((v: string) => {
            this.inputText = v;
          })
          .onSubmit(() => {
            this.send();
          })
        Button(this.asking ? '思考中' : '发送')
          .fontSize(AppTheme.FONT_BODY)
          .enabled(!this.asking)
          .fontColor('#FFFFFF')
          .width(92)
          .height(46)
          .backgroundColor(this.asking ? AI_VIOLET : AppTheme.PRIMARY)
          .borderRadius(999)
          .onClick(() => {
            this.send();
          })
      }
      .width('100%')
      .padding(AppTheme.SPACE_M)
      .borderRadius(28)
      .backgroundColor('rgba(255,255,255,0.88)')
      .border({ width: 1.2, color: AI_BORDER })
      .shadow({ radius: 24, color: 'rgba(31,62,68,0.10)', offsetX: 0, offsetY: 10 })
    }
    .layoutWeight(1)
    .height('100%')
    .padding(AppTheme.SPACE_L)
    .borderRadius(30)
    .backgroundColor('rgba(255,255,255,0.72)')
    .border({ width: 1.2, color: AI_BORDER })
    .shadow({ radius: 28, color: 'rgba(31,62,68,0.10)', offsetX: 0, offsetY: 12 })
  }

  @Builder
  compactSessionRow(cs: ChatSessionInfo, index: number) {
    Row({ space: 8 }) {
      Column()
        .width(7)
        .height(7)
        .borderRadius(4)
        .backgroundColor(this.selectedChatIndex === index ? AppTheme.PRIMARY : 'rgba(18,24,24,0.16)')
      Text(cs.title)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(this.selectedChatIndex === index ? AppTheme.INK : AppTheme.TEXT_SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .onClick(() => {
          this.selectChat(index);
        })
      Text('×')
        .fontSize(16)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .width(24)
        .height(24)
        .textAlign(TextAlign.Center)
        .borderRadius(12)
        .backgroundColor('rgba(255,92,92,0.08)')
        .onClick(() => {
          this.deleteChatSession(index);
        })
    }
    .width('100%')
    .height(34)
    .padding({ left: 10, right: 10 })
    .borderRadius(14)
    .backgroundColor(this.selectedChatIndex === index ? AppTheme.PRIMARY_LIGHT : 'rgba(18,24,24,0.03)')
  }

  @Builder
  compactMessageBubble(m: UiChatMessage) {
    Column({ space: 5 }) {
      Row() {
        Text(m.role === 'user' ? '老师' : 'AI')
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(m.role === 'user' ? AI_BLUE : AppTheme.PRIMARY)
        Blank()
        if (m.streaming) {
          Text('生成中')
            .fontSize(10)
            .fontColor(AI_VIOLET)
        }
      }
      .width('100%')
      if (m.warning !== '') {
        Text(`!  ${m.warning}`)
          .fontSize(10)
          .fontColor('#8A5200')
          .lineHeight(16)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .borderRadius(10)
          .backgroundColor('#FFF7E6')
          .border({ width: 1, color: '#F3CF85' })
      }
      Text(m.content + (m.streaming ? ' ▌' : ''))
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .lineHeight(18)
        .maxLines(5)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (m.sources.length > 0) {
        Text(`来源：${m.sources.join('；')}`)
          .fontSize(10)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(18)
    .backgroundColor(m.role === 'user' ? 'rgba(63,125,255,0.10)' : 'rgba(255,255,255,0.76)')
    .border({ width: 1, color: m.role === 'user' ? 'rgba(63,125,255,0.18)' : AI_BORDER })
  }

  @Builder
  teacherCompactAiPane() {
    Column({ space: AppTheme.SPACE_M }) {
      Row() {
        Column({ space: 3 }) {
          Text('AI 追问')
            .fontSize(AppTheme.FONT_BODY)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK)
          Text('辅助解释课堂热区')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Text('+')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#121818')
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .borderRadius(16)
          .backgroundColor(AppTheme.PRIMARY)
          .onClick(() => {
            this.newSession();
          })
      }
      .width('100%')

      Column({ space: AppTheme.SPACE_S }) {
        Text('最近会话')
          .fontSize(11)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .width('100%')
        if (this.chatSessions.length === 0) {
          Text('暂无会话')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .height(42)
            .width('100%')
        } else {
          List({ space: 6 }) {
            ForEach(this.chatSessions, (cs: ChatSessionInfo, index: number) => {
              ListItem() {
                this.compactSessionRow(cs, index)
              }
            }, (cs: ChatSessionInfo) => `${cs.id}`)
          }
          .height(96)
          .width('100%')
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .padding(AppTheme.SPACE_M)
      .borderRadius(22)
      .backgroundColor('rgba(255,255,255,0.70)')
      .border({ width: 1, color: AI_BORDER })

      Column({ space: AppTheme.SPACE_S }) {
        Row() {
          Text(this.selectedChatIndex >= 0 && this.selectedChatIndex < this.chatSessions.length ?
            this.chatSessions[this.selectedChatIndex].title : '临时追问')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.INK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
          Text(this.asking ? '思考' : '就绪')
            .fontSize(10)
            .fontColor(this.asking ? AI_VIOLET : AppTheme.PRIMARY)
        }
        .width('100%')

        if (this.messages.length === 0) {
          Column({ space: 8 }) {
            Text('可以追问热词成因')
              .fontSize(AppTheme.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.INK)
            Text('例如：为什么学生都在问中序遍历？')
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_TERTIARY)
              .textAlign(TextAlign.Center)
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          List({ space: AppTheme.SPACE_S, scroller: this.msgScroller }) {
            ForEach(this.messages, (m: UiChatMessage, index: number) => {
              ListItem() {
                this.compactMessageBubble(m)
              }
            }, (m: UiChatMessage, index: number) => `${index}_${m.role}_${m.content.length}_${m.streaming}_compact`)
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Auto)
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding(AppTheme.SPACE_M)
      .borderRadius(24)
      .backgroundColor('rgba(255,255,255,0.62)')
      .border({ width: 1, color: AI_BORDER })

      Row({ space: AppTheme.SPACE_S }) {
        TextInput({ text: this.inputText, placeholder: '向 AI 追问…' })
          .layoutWeight(1)
          .fontSize(AppTheme.FONT_CAPTION)
          .height(42)
          .borderRadius(21)
          .backgroundColor('rgba(18,24,24,0.04)')
          .onChange((v: string) => {
            this.inputText = v;
          })
          .onSubmit(() => {
            this.send();
          })
        Button(this.asking ? '…' : '问')
          .fontSize(AppTheme.FONT_CAPTION)
          .enabled(!this.asking)
          .fontColor('#FFFFFF')
          .width(58)
          .height(42)
          .backgroundColor(this.asking ? AI_VIOLET : AppTheme.PRIMARY)
          .borderRadius(21)
          .onClick(() => {
            this.send();
          })
      }
      .width('100%')
    }
    .width(420)
    .height('100%')
    .padding(AppTheme.SPACE_L)
    .borderRadius(30)
    .backgroundColor('rgba(255,255,255,0.70)')
    .border({ width: 1.2, color: AI_BORDER })
    .shadow({ radius: 24, color: 'rgba(31,62,68,0.10)', offsetX: 0, offsetY: 12 })
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 36,
          colors: [
            ['#F8FCFA', 0],
            [AI_BG, 0.52],
            ['#EEF3FF', 1]
          ]
        })
      Column()
        .width(560)
        .height(520)
        .borderRadius(70)
        .rotate({ angle: -18 })
        .backgroundColor('rgba(5,206,145,0.10)')
        .position({ x: -180, y: -120 })
      Column({ space: AppTheme.SPACE_L }) {
        this.pageHeader()
        if (GlobalState.isTeacher()) {
          Row({ space: AppTheme.SPACE_L }) {
            this.teacherInsightPane()
            this.teacherCompactAiPane()
          }
          .layoutWeight(1)
          .width('100%')
          .alignItems(VerticalAlign.Top)
        } else {
          Row({ space: AppTheme.SPACE_L }) {
            this.historyPane()
            this.chatPane()
          }
          .layoutWeight(1)
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: AppTheme.SPACE_XXL, right: AppTheme.SPACE_XXL, top: 28, bottom: AppTheme.SPACE_XXL })
      .opacity(this.pageReady ? 1 : 0)
      .translate({ x: 0, y: this.pageReady ? 0 : 24 })
      .scale({ x: this.pageReady ? 1 : 0.986, y: this.pageReady ? 1 : 0.986 })
      .animation({ duration: 360, curve: Curve.EaseOut })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AI_BG)
  }
}
