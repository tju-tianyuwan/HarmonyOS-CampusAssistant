import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { ChatMessageInfo, ChatSessionInfo, UiChatMessage } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

@Component
export struct CourseAiPage {
  @State chatSessions: ChatSessionInfo[] = [];
  @State selectedChatIndex: number = -1;
  @State messages: UiChatMessage[] = [];
  @State inputText: string = '';
  @State asking: boolean = false;
  private msgScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadChatSessions();
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
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
        const ui: UiChatMessage = { role: m.role, content: m.content, sources: sources, streaming: false };
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

    const userMsg: UiChatMessage = { role: 'user', content: q, sources: [], streaming: false };
    const holder: UiChatMessage = { role: 'assistant', content: '', sources: [], streaming: true };
    this.messages.push(userMsg);
    this.messages.push(holder);
    this.msgScroller.scrollEdge(Edge.Bottom);

    Api.streamAsk(chatId, q, memory, {
      onSources: (sources: string[]) => {
        const last: UiChatMessage = this.messages[this.messages.length - 1];
        const next: UiChatMessage =
          { role: 'assistant', content: last.content, sources: sources, streaming: true };
        this.replaceLastMessage(next);
      },
      onDelta: (delta: string) => {
        const last: UiChatMessage = this.messages[this.messages.length - 1];
        const next: UiChatMessage =
          { role: 'assistant', content: last.content + delta, sources: last.sources, streaming: true };
        this.replaceLastMessage(next);
        this.msgScroller.scrollEdge(Edge.Bottom);
      },
      onDone: () => {
        const last: UiChatMessage = this.messages[this.messages.length - 1];
        const next: UiChatMessage =
          { role: 'assistant', content: last.content, sources: last.sources, streaming: false };
        this.replaceLastMessage(next);
        this.asking = false;
      },
      onError: (msg: string) => {
        const last: UiChatMessage = this.messages[this.messages.length - 1];
        const next: UiChatMessage = {
          role: 'assistant',
          content: last.content === '' ? `（请求失败：${msg}）` : last.content,
          sources: last.sources,
          streaming: false
        };
        this.replaceLastMessage(next);
        this.asking = false;
      }
    });
  }

  @Builder
  pageHeader() {
    Row({ space: AppTheme.SPACE_M }) {
      Text('AI')
        .fontSize(AppTheme.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.INK)
      Text('课程知识库')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.PRIMARY)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(999)
        .backgroundColor(AppTheme.PRIMARY_LIGHT)
      Blank()
    }
    .width('100%')
    .height(44)
  }

  @Builder
  historyPane() {
    Column({ space: AppTheme.SPACE_M }) {
      Row() {
        Text('历史会话')
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_SECONDARY)
        Blank()
        Text('+ 新会话')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.PRIMARY)
          .onClick(() => {
            this.newSession();
          })
      }
      .width('100%')

      if (this.chatSessions.length === 0) {
        Column({ space: AppTheme.SPACE_S }) {
          Text('暂无历史会话')
            .fontSize(AppTheme.FONT_BODY)
            .fontColor(AppTheme.TEXT_TERTIARY)
          Text('开始提问后会保存当前会话')
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
              Text(cs.title)
                .fontSize(AppTheme.FONT_BODY)
                .fontColor(this.selectedChatIndex === index ? AppTheme.PRIMARY : AppTheme.TEXT_PRIMARY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .padding(AppTheme.SPACE_S)
                .borderRadius(AppTheme.RADIUS_BTN)
                .backgroundColor(this.selectedChatIndex === index ? AppTheme.PRIMARY_LIGHT : 'transparent')
                .onClick(() => {
                  this.selectChat(index);
                })
            }
          }, (cs: ChatSessionInfo) => `${cs.id}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width(240)
    .height('100%')
    .padding(AppTheme.SPACE_M)
    .borderRadius(AppTheme.RADIUS_CARD)
    .backgroundColor(AppTheme.BG_CARD)
  }

  @Builder
  messageBubble(m: UiChatMessage) {
    Row() {
      if (m.role === 'user') {
        Blank()
      }
      Column({ space: AppTheme.SPACE_XS }) {
        Text(m.role === 'user' ? '我' : 'AI')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(m.role === 'user' ? AppTheme.PRIMARY : AppTheme.SUCCESS)
        Text(m.content + (m.streaming ? ' ▌' : ''))
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .lineHeight(22)
        if (m.sources.length > 0) {
          Text(`来源：${m.sources.join('；')}`)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
      }
      .constraintSize({ maxWidth: '76%' })
      .padding(AppTheme.SPACE_M)
      .borderRadius(18)
      .backgroundColor(m.role === 'user' ? AppTheme.PRIMARY_LIGHT : AppTheme.BG_CARD)
      .alignItems(HorizontalAlign.Start)
      if (m.role !== 'user') {
        Blank()
      }
    }
    .width('100%')
  }

  @Builder
  chatPane() {
    Column({ space: AppTheme.SPACE_M }) {
      if (this.messages.length === 0) {
        Column({ space: AppTheme.SPACE_S }) {
          Text('向课程 AI 提问')
            .fontSize(AppTheme.FONT_SUBTITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TEXT_SECONDARY)
          Text('它会基于当前课程已入库的资料回答')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
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
          .onChange((v: string) => {
            this.inputText = v;
          })
          .onSubmit(() => {
            this.send();
          })
        Button(this.asking ? '思考中' : '发送')
          .fontSize(AppTheme.FONT_BODY)
          .enabled(!this.asking)
          .backgroundColor(AppTheme.PRIMARY)
          .borderRadius(999)
          .onClick(() => {
            this.send();
          })
      }
      .width('100%')
      .padding(AppTheme.SPACE_M)
      .borderRadius(24)
      .backgroundColor(AppTheme.BG_CARD)
    }
    .layoutWeight(1)
    .height('100%')
  }

  build() {
    Column({ space: AppTheme.SPACE_L }) {
      this.pageHeader()
      Row({ space: AppTheme.SPACE_L }) {
        this.historyPane()
        this.chatPane()
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .height('100%')
    .padding(AppTheme.SPACE_XL)
    .backgroundColor(AppTheme.BG_PAGE)
  }
}
