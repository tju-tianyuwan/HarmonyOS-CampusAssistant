import { TouchMotion } from '../common/TouchMotion';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { LearningTheme as AppTheme } from '../common/LearningTheme';
import { MobileLayout } from '../common/MobileLayout';
import { MobileTabs } from '../common/components/MobileTabs';
import { ChatMessageInfo, ChatSessionInfo, KB_FALLBACK_WARNING, Note, UiChatMessage } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';
import { transferService, TransferNote } from '../service/collab/TransferService';

/** 划词命令待回填动作 */
interface PendingApply {
  mode: string; // none | insertAfter | replaceRange
  start: number;
  end: number;
}

/**
 * AI 笔记：
 * 左栏历史会话 | 主区 MD 编辑器 | 右侧 AI 面板。
 */
@Component
export struct AiNotePage {
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  onBack: () => void = () => {
  };
  initialNoteId: number = -1;
  createOnAppear: boolean = false;
  readOnly: boolean = false;
  // 左栏
  @State leftOpen: boolean = true;
  @State chatSessions: ChatSessionInfo[] = [];
  @State selectedChatIndex: number = -1;
  @State myNotes: Note[] = [];
  @State selectedNoteIndex: number = -1;
  // 编辑器
  @State editorText: string = '';
  @State noteTitle: string = '';
  @State selStart: number = 0;
  @State selEnd: number = 0;
  @State dirty: boolean = false;
  // AI 面板
  @State aiOpen: boolean = true;
  @State compact: boolean = false;
  @State compactTab: string = 'editor';
  @State messages: UiChatMessage[] = [];
  @State inputText: string = '';
  @State asking: boolean = false;
  @State carryNote: boolean = true;
  @State refSelected: boolean[] = [];
  private pending: PendingApply = { mode: 'none', start: 0, end: 0 };
  private msgScroller: Scroller = new Scroller();
  private answerGeneration: number = 0;
  private cancelStream: (() => void) | null = null;

  private stopAnswer(): void {
    this.answerGeneration++;
    if (this.cancelStream !== null) { this.cancelStream(); this.cancelStream = null; }
    this.asking = false;
    this.messages = this.messages.map((message: UiChatMessage): UiChatMessage => {
      return { role: message.role, content: message.content, sources: message.sources, warning: message.warning, streaming: false };
    });
  }

  aboutToAppear(): void {
    transferService.setNoteProvider((): TransferNote | null => this.currentNote() === null ? null :
      { title: this.noteTitle, kind: 'md', content: this.editorText });
    this.loadChatSessions();
    if (this.createOnAppear) {
      this.createNote();
    } else {
      this.loadNotes();
    }
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  aboutToDisappear(): void {
    this.stopAnswer();
    transferService.setNoteProvider(null);
    if (this.cancelStream !== null) { this.cancelStream(); this.cancelStream = null; }
  }

  private currentNote(): Note | null {
    return this.selectedNoteIndex < 0 || this.selectedNoteIndex >= this.myNotes.length ?
      null : this.myNotes[this.selectedNoteIndex];
  }

  private canEditCurrent(): boolean {
    const n: Note | null = this.currentNote();
    return n !== null && !this.readOnly && n.owner_id === GlobalState.userId();
  }

  // ---------- 数据加载 ----------
  private async loadChatSessions(): Promise<void> {
    try {
      this.chatSessions = JSON.parse(await Api.get(
        `/chat/sessions?class_course_id=${GlobalState.courseId()}&user_id=${GlobalState.userId()}`)) as ChatSessionInfo[];
    } catch (e) {
      this.chatSessions = [];
    }
  }

  private async loadNotes(): Promise<void> {
    try {
      const targetNoteId: number = this.initialNoteId >= 0 ? this.initialNoteId : GlobalState.pendingOpenNoteId;
      const all: Note[] = JSON.parse(await Api.get(
        `/notes?class_course_id=${GlobalState.courseId()}&user_id=${GlobalState.userId()}`)) as Note[];
      if (this.readOnly && this.initialNoteId >= 0) {
        this.myNotes = all.filter((n: Note) => n.kind === 'md' &&
          (n.owner_id === GlobalState.userId() || n.visibility === 'shared'));
      } else {
        this.myNotes = all.filter((n: Note) => n.owner_id === GlobalState.userId() && n.kind === 'md');
      }
      this.refSelected = this.myNotes.map((n: Note) => false);
      if (targetNoteId >= 0) {
        for (let i = 0; i < this.myNotes.length; i++) {
          if (this.myNotes[i].id === targetNoteId) {
            this.selectNote(i);
            GlobalState.pendingOpenNoteId = -1;
            return;
          }
        }
        GlobalState.pendingOpenNoteId = -1;
      }
      if (this.myNotes.length > 0 && this.selectedNoteIndex < 0) {
        this.selectNote(0);
      }
    } catch (e) {
      this.myNotes = [];
    }
  }

  private selectNote(index: number): void {
    this.selectedNoteIndex = index;
    const n: Note | null = this.currentNote();
    if (n !== null) {
      this.editorText = n.content;
      this.noteTitle = n.title;
      this.dirty = false;
    }
  }

  private selectNoteById(noteId: number): boolean {
    for (let i = 0; i < this.myNotes.length; i++) {
      if (this.myNotes[i].id === noteId) {
        this.selectNote(i);
        return true;
      }
    }
    return false;
  }

  private async createNote(): Promise<void> {
    interface NoteBody {
      class_course_id: number;
      session_id: number | null;
      owner_id: number;
      title: string;
      kind: string;
      content: string;
    }

    const body: NoteBody = {
      class_course_id: GlobalState.courseId(),
      session_id: GlobalState.pendingNoteSessionId >= 0 ? GlobalState.pendingNoteSessionId : null,
      owner_id: GlobalState.userId(),
      title: '随堂笔记',
      kind: 'md',
      content: ''
    };
    try {
      const created: Note = JSON.parse(await Api.post('/notes', body)) as Note;
      GlobalState.pendingNoteSessionId = -1;
      await this.loadNotes();
      if (!this.selectNoteById(created.id) && this.myNotes.length > 0) {
        this.selectNote(this.myNotes.length - 1);
      }
      this.toast('已新建笔记');
    } catch (e) {
      this.toast(`新建失败：${(e as Error).message}`);
    }
  }

  private async persistNote(successText: string): Promise<void> {
    const n: Note | null = this.currentNote();
    if (n === null || !this.canEditCurrent()) {
      this.toast('当前笔记为只读');
      return;
    }
    interface UpdateBody {
      title: string;
      content: string;
    }

    const body: UpdateBody = { title: this.noteTitle, content: this.editorText };
    try {
      await Api.put(`/notes/${n.id}`, body);
      n.content = this.editorText;
      n.title = this.noteTitle;
      this.dirty = false;
      this.toast(successText);
    } catch (e) {
      this.toast(`保存失败：${(e as Error).message}`);
    }
  }

  private async saveNote(): Promise<void> {
    await this.persistNote('已保存');
  }

  private async renameNote(): Promise<void> {
    if (this.noteTitle.trim() === '') {
      this.toast('笔记标题不能为空');
      return;
    }
    await this.persistNote('已重命名');
  }

  private async deleteCurrentNote(): Promise<void> {
    const n: Note | null = this.currentNote();
    if (n === null || !this.canEditCurrent()) {
      this.toast('当前笔记为只读');
      return;
    }
    const result = await promptAction.showDialog({
      title: '删除笔记',
      message: `确定永久删除“${n.title}”吗？`,
      buttons: [
        { text: '取消', color: AppTheme.TEXT_SECONDARY },
        { text: '删除', color: AppTheme.DANGER }
      ]
    });
    if (result.index !== 1) {
      return;
    }
    try {
      const deletedIndex: number = this.selectedNoteIndex;
      await Api.remove(`/notes/${n.id}?user_id=${GlobalState.userId()}`);
      this.myNotes = this.myNotes.filter((item: Note) => item.id !== n.id);
      this.refSelected = this.myNotes.map((item: Note) => false);
      this.selectedNoteIndex = -1;
      this.editorText = '';
      this.noteTitle = '';
      this.dirty = false;
      if (this.myNotes.length > 0) {
        this.selectNote(Math.min(deletedIndex, this.myNotes.length - 1));
      }
      this.toast('笔记已删除');
    } catch (e) {
      this.toast(`删除笔记失败：${(e as Error).message}`);
    }
  }

  private async selectChat(index: number): Promise<void> {
    if (this.asking) { this.stopAnswer(); }
    this.selectedChatIndex = index;
    const cs: ChatSessionInfo = this.chatSessions[index];
    try {
      const list: ChatMessageInfo[] = JSON.parse(
        await Api.get(`/chat/sessions/${cs.id}/messages`)) as ChatMessageInfo[];
      if (this.chatSessions[this.selectedChatIndex]?.id !== cs.id) { return; }
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
    }
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
      this.toast('对话已删除');
    } catch (e) {
      this.toast(`删除对话失败：${(e as Error).message}`);
    }
  }

  // ---------- 问答 ----------
  private buildContext(): string {
    const parts: string[] = [];
    if (this.carryNote && this.editorText.trim() !== '') {
      parts.push(`[当前笔记：${this.noteTitle}]\n${this.editorText}`);
    }
    for (let i = 0; i < this.myNotes.length; i++) {
      if (this.refSelected[i] && i !== this.selectedNoteIndex) {
        parts.push(`[引用笔记：${this.myNotes[i].title}]\n${this.myNotes[i].content}`);
      }
    }
    return parts.join('\n---\n');
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
      title: firstQuestion.length > 12 ? firstQuestion.substring(0, 12) + '…' : firstQuestion
    };
    const generation = this.answerGeneration;
    const cs: ChatSessionInfo = JSON.parse(await Api.post('/chat/sessions', body)) as ChatSessionInfo;
    if (generation !== this.answerGeneration) { return -1; }
    this.chatSessions = [cs].concat(this.chatSessions);
    this.selectedChatIndex = 0;
    this.messages = [];
    return cs.id;
  }

  private replaceLastMessage(m: UiChatMessage): void {
    this.messages.splice(this.messages.length - 1, 1, m);
  }

  private async send(question: string): Promise<void> {
    if (this.readOnly) {
      this.toast('班级笔记为只读，仅支持查看');
      return;
    }
    const q: string = question.trim();
    if (q === '' || this.asking) {
      return;
    }
    this.aiOpen = true;
    this.asking = true;
    const generation = ++this.answerGeneration;
    let chatId: number = -1;
    try {
      chatId = await this.ensureChatSession(q);
    } catch (e) {
      this.toast(`创建会话失败：${(e as Error).message}`);
      this.asking = false;
      return;
    }
    if (generation !== this.answerGeneration || chatId < 0) { return; }
    const userMsg: UiChatMessage = { role: 'user', content: q, sources: [], warning: '', streaming: false };
    const holder: UiChatMessage = { role: 'assistant', content: '', sources: [], warning: '', streaming: true };
    this.messages.push(userMsg);
    this.messages.push(holder);
    this.msgScroller.scrollEdge(Edge.Bottom);

    this.cancelStream = Api.streamAsk(chatId, q, this.buildContext(), {
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
        this.applyPending(next.content);
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
        this.pending = { mode: 'none', start: 0, end: 0 };
      }
    });
  }

  // ---------- 编辑器回填 ----------
  private insertAt(pos: number, text: string): void {
    if (!this.canEditCurrent()) {
      this.toast('当前笔记为只读');
      return;
    }
    const p: number = Math.min(Math.max(pos, 0), this.editorText.length);
    this.editorText = this.editorText.substring(0, p) + text + this.editorText.substring(p);
    this.dirty = true;
    this.saveNote();
  }

  private replaceRange(start: number, end: number, text: string): void {
    if (!this.canEditCurrent()) {
      this.toast('当前笔记为只读');
      return;
    }
    const s: number = Math.min(Math.max(start, 0), this.editorText.length);
    const e: number = Math.min(Math.max(end, s), this.editorText.length);
    this.editorText = this.editorText.substring(0, s) + text + this.editorText.substring(e);
    this.dirty = true;
    this.saveNote();
  }

  private applyPending(answer: string): void {
    if (this.pending.mode === 'insertAfter') {
      this.insertAt(this.pending.end, `\n${answer}\n`);
      this.toast('AI 结果已插入笔记');
    } else if (this.pending.mode === 'replaceRange') {
      this.replaceRange(this.pending.start, this.pending.end, answer);
      this.toast('AI 结果已替换选中内容');
    }
    this.pending = { mode: 'none', start: 0, end: 0 };
  }

  private selectedText(): string {
    if (this.selEnd > this.selStart) {
      return this.editorText.substring(this.selStart, this.selEnd);
    }
    return '';
  }

  private runCommand(cmd: string): void {
    const sel: string = this.selectedText();
    if (sel === '') {
      return;
    }
    if (cmd !== 'ask' && !this.canEditCurrent()) {
      this.toast('当前笔记为只读');
      return;
    }
    if (cmd === 'ask') {
      this.pending = { mode: 'none', start: 0, end: 0 };
      this.send(sel);
    } else if (cmd === 'summarize') {
      this.pending = { mode: 'insertAfter', start: this.selStart, end: this.selEnd };
      this.send(`请总结以下内容：\n${sel}`);
    } else if (cmd === 'explain') {
      this.pending = { mode: 'insertAfter', start: this.selStart, end: this.selEnd };
      this.send(`请解释以下内容：\n${sel}`);
    } else if (cmd === 'continue') {
      this.pending = { mode: 'insertAfter', start: this.selStart, end: this.selEnd };
      this.send(`请续写以下内容，直接给出续写文本：\n${sel}`);
    }
  }

  private copyText(text: string): void {
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data);
    this.toast('已复制');
  }

  // ---------- UI ----------
  @Builder
  pageHeader() {
    Row({ space: AppTheme.SPACE_M }) {
      Text('‹')
        .fontSize(28)
        .fontColor(AppTheme.INK)
        .width(36)
        .height(36)
        .textAlign(TextAlign.Center)
        .borderRadius(18)
        .backgroundColor(AppTheme.BG_CARD)
        .onClick(() => {
          this.onBack();
        })
      Text('AI 笔记')
        .fontSize(AppTheme.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.INK)
      Blank()
    }
    .width('100%')
    .height(44)
  }

  @Builder
  cmdButton(label: string, cmd: string) {
    Text(label)
      .fontSize(AppTheme.FONT_CAPTION)
      .fontColor(AppTheme.PRIMARY)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(AppTheme.RADIUS_BTN)
      .backgroundColor(AppTheme.PRIMARY_LIGHT)
      .onClick(() => {
        this.runCommand(cmd);
      })
  }

  @Builder
  chevronMark(pointRight: boolean, color: string) {
    if (pointRight) {
      Column()
        .width(10)
        .height(10)
        .border({ width: { top: 2, right: 2 }, color: color })
        .rotate({ angle: 45 })
    } else {
      Column()
        .width(10)
        .height(10)
        .border({ width: { top: 2, left: 2 }, color: color })
        .rotate({ angle: -45 })
    }
  }

  @Builder
  sidebarToggleButton() {
    Stack({ alignContent: Alignment.Center }) {
      this.chevronMark(!this.leftOpen, AppTheme.TEXT_SECONDARY)
    }
    .width(36)
    .height(36)
    .borderRadius(18)
    .backgroundColor(AppTheme.BG_CARD)
    .onClick(() => {
      this.leftOpen = !this.leftOpen;
    })
  }

  @Builder
  aiToggleButton() {
    Row({ space: AppTheme.SPACE_S }) {
      Text('AI')
        .fontSize(AppTheme.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.PRIMARY)
      Stack({ alignContent: Alignment.Center }) {
        this.chevronMark(this.aiOpen, AppTheme.PRIMARY)
      }
      .width(20)
      .height(20)
    }
    .height(38)
    .padding({ left: 12, right: 12 })
    .borderRadius(999)
    .backgroundColor(AppTheme.PRIMARY_LIGHT)
    .onClick(() => {
      this.aiOpen = !this.aiOpen;
    })
  }

  @Builder
  leftPaneView() {
    Column({ space: AppTheme.SPACE_M }) {
      Row() {
        Text('历史会话')
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_SECONDARY)
        Blank()
        if (!this.readOnly) {
          Text('+ 新会话')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.PRIMARY)
            .onClick(() => {
              this.selectedChatIndex = -1;
              this.messages = [];
            })
        }
      }
      .width('100%')

      if (this.chatSessions.length === 0) {
        Column({ space: AppTheme.SPACE_S }) {
          Text('暂无历史会话')
            .fontSize(AppTheme.FONT_BODY)
            .fontColor(AppTheme.TEXT_TERTIARY)
          Text('向 AI 提问后会自动保存在这里')
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
              Row({ space: AppTheme.SPACE_XS }) {
                Text(cs.title)
                  .fontSize(AppTheme.FONT_BODY)
                  .fontColor(this.selectedChatIndex === index ? AppTheme.PRIMARY : AppTheme.TEXT_PRIMARY)
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
                  .backgroundColor(AppTheme.tagBg(AppTheme.DANGER))
                  .onClick(() => {
                    this.deleteChatSession(index);
                  })
              }
              .width('100%')
              .padding(AppTheme.SPACE_S)
              .borderRadius(AppTheme.RADIUS_BTN)
              .backgroundColor(this.selectedChatIndex === index ? AppTheme.PRIMARY_LIGHT : 'transparent')
            }
          }, (cs: ChatSessionInfo) => `${cs.id}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width(this.compact ? '100%' : 220)
    .height('100%')
    .padding(AppTheme.SPACE_M)
    .borderRadius(AppTheme.RADIUS_CARD)
    .backgroundColor(AppTheme.BG_CARD)
  }

  @Builder
  editorView() {
    Column({ space: AppTheme.SPACE_M }) {
      if (this.compact) {
        TextInput({ text: this.noteTitle, placeholder: '笔记标题' }).enabled(this.canEditCurrent())
          .onChange((value: string) => { if (value !== this.noteTitle) { this.noteTitle = value; this.dirty = true; } })
        Row({ space: 8 }) {
          if (this.dirty) { Text('未保存').fontSize(12).fontColor(AppTheme.WARNING) }
          Blank()
          if (this.canEditCurrent()) {
            Button('保存').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY).onClick(() => { this.saveNote(); })
            Button('删除').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).fontColor(AppTheme.DANGER).backgroundColor(Color.Transparent).onClick(() => { this.deleteCurrentNote(); })
          }
        }.width('100%')
      } else {
      Row({ space: AppTheme.SPACE_M }) {
        this.sidebarToggleButton()
        TextInput({ text: this.noteTitle, placeholder: '笔记标题' })
          .fontSize(AppTheme.FONT_SUBTITLE)
          .layoutWeight(1)
          .backgroundColor('transparent')
          .enabled(this.canEditCurrent())
          .onChange((v: string) => {
            this.noteTitle = v;
            this.dirty = true;
          })
        if (this.dirty) {
          Text('未保存').fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.WARNING)
        }
        if (this.canEditCurrent()) {
          Button('重命名').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
            .fontSize(AppTheme.FONT_BODY)
            .backgroundColor(AppTheme.BG_CARD)
            .fontColor(AppTheme.TEXT_SECONDARY)
            .borderRadius(AppTheme.RADIUS_BTN)
            .onClick(() => {
              this.renameNote();
            })
          Button('保存').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
            .fontSize(AppTheme.FONT_BODY)
            .backgroundColor(AppTheme.PRIMARY)
            .borderRadius(999)
            .onClick(() => {
              this.saveNote();
            })
          Button('删除').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
            .fontSize(AppTheme.FONT_BODY)
            .backgroundColor(AppTheme.tagBg(AppTheme.DANGER))
            .fontColor(AppTheme.DANGER)
            .borderRadius(AppTheme.RADIUS_BTN)
            .onClick(() => {
              this.deleteCurrentNote();
            })
        } else if (this.currentNote() !== null) {
          Text('只读')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(999)
            .backgroundColor(AppTheme.BG_CARD)
        }
        this.aiToggleButton()
      }
      .width('100%')
      }

      if (this.selEnd > this.selStart && !this.readOnly) {
        Flex({ wrap: FlexWrap.Wrap }) {
          Text('划词命令：').fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.TEXT_TERTIARY)
          this.cmdButton('问 AI', 'ask')
          if (this.canEditCurrent()) {
            this.cmdButton('总结', 'summarize')
            this.cmdButton('解释', 'explain')
            this.cmdButton('续写', 'continue')
          }
        }
        .width('100%')
      }

      if (this.currentNote() === null) {
        Column({ space: AppTheme.SPACE_M }) {
          Text('还没有笔记').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_TERTIARY)
          if (!this.readOnly) {
            Button('新建随堂笔记').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
              .backgroundColor(AppTheme.PRIMARY)
              .borderRadius(999)
              .onClick(() => {
                this.createNote();
              })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        TextArea({ text: this.editorText, placeholder: '在此记录 Markdown 笔记，选中文本可唤起 AI 命令…' })
          .width('100%')
          .layoutWeight(1)
          .fontSize(AppTheme.FONT_BODY)
          .backgroundColor(AppTheme.BG_CARD)
          .borderRadius(AppTheme.RADIUS_CARD)
          .enabled(this.canEditCurrent())
          .onChange((v: string) => {
            this.editorText = v;
            this.dirty = true;
          })
          .onTextSelectionChange((start: number, end: number) => {
            this.selStart = start;
            this.selEnd = end;
          })
      }
    }
    .layoutWeight(1)
    .height('100%')
  }

  @Builder
  aiPanelView() {
    Column({ space: AppTheme.SPACE_M }) {
      Text('AI 助手 · 仅依据本课程知识库作答')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .width('100%')

      Row({ space: AppTheme.SPACE_S }) {
        Toggle({ type: ToggleType.Switch, isOn: this.carryNote })
          .selectedColor(AppTheme.PRIMARY)
          .height(20)
          .onChange((on: boolean) => {
            this.carryNote = on;
          })
        Text('携带当前笔记').fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.TEXT_SECONDARY)
        Blank()
      }
      .width('100%')

      if (this.myNotes.length > 1) {
        Text('@ 引用其他笔记：')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.myNotes, (n: Note, index: number) => {
            if (index !== this.selectedNoteIndex) {
              Text(`@${n.title}`)
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(this.refSelected[index] ? '#FFFFFF' : AppTheme.TEXT_SECONDARY)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .margin({ right: 6, bottom: 6 })
                .borderRadius(AppTheme.RADIUS_TAG)
                .backgroundColor(this.refSelected[index] ? AppTheme.PRIMARY : AppTheme.BG_PAGE)
                .onClick(() => {
                  const next: boolean[] = this.refSelected.slice(0);
                  next[index] = !next[index];
                  this.refSelected = next;
                })
            }
          }, (n: Note) => `${n.id}`)
        }
        .width('100%')
      }

      List({ space: AppTheme.SPACE_M, scroller: this.msgScroller }) {
        ForEach(this.messages, (m: UiChatMessage, index: number) => {
          ListItem() {
            Column({ space: AppTheme.SPACE_XS }) {
              Text(m.role === 'user' ? '我' : 'AI')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(m.role === 'user' ? AppTheme.PRIMARY : AppTheme.SUCCESS)
              if (m.warning !== '') {
                Row({ space: 8 }) {
                  Text('!')
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#9A5B00')
                    .width(22)
                    .height(22)
                    .textAlign(TextAlign.Center)
                    .borderRadius(11)
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
                .padding({ left: 9, right: 9, top: 8, bottom: 8 })
                .borderRadius(12)
                .backgroundColor('#FFF7E6')
                .border({ width: 1, color: '#F3CF85' })
              }
              Text(m.content + (m.streaming ? ' ▌' : ''))
                .fontSize(AppTheme.FONT_BODY)
                .fontColor(AppTheme.TEXT_PRIMARY)
                .lineHeight(20)
              if (m.sources.length > 0) {
                Text(`来源：${m.sources.join('；')}`)
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.TEXT_TERTIARY)
              }
              if (m.role === 'assistant' && !m.streaming && m.content !== '') {
                Row({ space: AppTheme.SPACE_S }) {
                  if (this.canEditCurrent()) {
                    Text('插入光标处')
                      .fontSize(AppTheme.FONT_CAPTION)
                      .fontColor(AppTheme.PRIMARY)
                      .onClick(() => {
                        this.insertAt(this.selStart, `\n${m.content}\n`);
                        this.toast('已插入');
                      })
                    Text('替换选区')
                      .fontSize(AppTheme.FONT_CAPTION)
                      .fontColor(AppTheme.PRIMARY)
                      .onClick(() => {
                        if (this.selEnd > this.selStart) {
                          this.replaceRange(this.selStart, this.selEnd, m.content);
                          this.toast('已替换');
                        } else {
                          this.toast('请先在编辑器中选中要替换的文本');
                        }
                      })
                  }
                  Text('复制')
                    .fontSize(AppTheme.FONT_CAPTION)
                    .fontColor(AppTheme.TEXT_SECONDARY)
                    .onClick(() => {
                      this.copyText(m.content);
                    })
                }
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(AppTheme.SPACE_S)
            .borderRadius(AppTheme.RADIUS_BTN)
            .backgroundColor(m.role === 'user' ? AppTheme.PRIMARY_LIGHT : 'transparent')
          }
        }, (m: UiChatMessage, index: number) => `${index}_${m.content.length}_${m.streaming}`)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)

      Row({ space: AppTheme.SPACE_S }) {
        TextInput({ text: this.inputText, placeholder: '就本课程内容提问…' })
          .layoutWeight(1)
          .fontSize(AppTheme.FONT_BODY)
          .enabled(!this.readOnly)
          .onChange((v: string) => {
            this.inputText = v;
          })
          .onSubmit(() => {
            const q: string = this.inputText;
            this.inputText = '';
            this.pending = { mode: 'none', start: 0, end: 0 };
            this.send(q);
          })
        Button(this.asking ? '停止' : '发送').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
          .fontSize(AppTheme.FONT_BODY)
          .enabled(!this.readOnly)
          .backgroundColor(AppTheme.PRIMARY)
          .borderRadius(999)
          .onClick(() => {
            if (this.asking) { this.stopAnswer(); return; }
            const q: string = this.inputText;
            this.inputText = '';
            this.pending = { mode: 'none', start: 0, end: 0 };
            this.send(q);
          })
      }
      .width('100%')
    }
    .width(this.compact ? '100%' : 290)
    .height('100%')
    .padding(AppTheme.SPACE_M)
    .borderRadius(AppTheme.RADIUS_CARD)
    .backgroundColor(AppTheme.BG_CARD)
  }

  build() {
    Column({ space: AppTheme.SPACE_M }) {
      this.pageHeader()
      if (this.compact) {
        if (MobileLayout.studentPhone()) {
          MobileTabs({ labels: ['笔记列表', '编辑', 'AI'], keys: ['list', 'editor', 'ai'], selected: this.compactTab,
            onSelect: (key: string) => { this.compactTab = key; } })
        } else {
        Row({ space: 8 }) {
          Button('笔记列表').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).onClick(() => { this.compactTab = 'list'; })
          Button('编辑').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).onClick(() => { this.compactTab = 'editor'; })
          Button('AI').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).onClick(() => { this.compactTab = 'ai'; })
        }.width('100%')
        }
        Row() {
          if (this.compactTab === 'list') { this.leftPaneView() }
          else if (this.compactTab === 'ai') { this.aiPanelView() }
          else { this.editorView() }
        }.width('100%').layoutWeight(1)
      } else {
      Row({ space: AppTheme.SPACE_L }) {
        if (this.leftOpen) {
          this.leftPaneView()
        }
        this.editorView()
        if (this.aiOpen) {
          this.aiPanelView()
        }
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Top)
      }
    }
    .width('100%')
    .height('100%')
    .padding(this.compact ? 12 : AppTheme.SPACE_XL)
    .backgroundColor(AppTheme.BG_PAGE)
    .onAreaChange((oldArea: Area, newArea: Area) => { this.compact = Number(newArea.width) < 1000; })
  }
}
