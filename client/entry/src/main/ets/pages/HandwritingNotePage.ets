import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { HandwritingBoard } from '../common/components/HandwritingBoard';
import { Note } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

/**
 * 手写笔记页：个人笔记卡片进入后，全屏书写 + 浮动操作栏。
 */
@Component
export struct HandwritingNotePage {
  onBack: () => void = () => {
  };
  initialNoteId: number = -1;
  createOnAppear: boolean = false;
  readOnly: boolean = false;
  @State notes: Note[] = [];
  @State selectedIndex: number = -1;
  @State editorText: string = '';
  @State noteTitle: string = '';
  @State dirty: boolean = false;
  @State sharing: boolean = false;
  /** 手写画板重建开关：切换笔记时强制重建组件加载新笔迹 */
  @State boardKey: number = 0;

  aboutToAppear(): void {
    if (this.createOnAppear) {
      this.createNote('handwriting');
    } else {
      this.loadNotes(true);
    }
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private current(): Note | null {
    return this.selectedIndex < 0 || this.selectedIndex >= this.notes.length ?
      null : this.notes[this.selectedIndex];
  }

  private isMine(n: Note): boolean {
    return n.owner_id === GlobalState.userId();
  }

  private canEditCurrent(): boolean {
    const n: Note | null = this.current();
    return n !== null && !this.readOnly && this.isMine(n);
  }

  private async loadNotes(selectFirst: boolean): Promise<void> {
    try {
      const all: Note[] = JSON.parse(await Api.get(
        `/notes?class_course_id=${GlobalState.courseId()}&user_id=${GlobalState.userId()}`)) as Note[];
      if (this.readOnly && this.initialNoteId >= 0) {
        this.notes = all.filter((n: Note) => n.kind === 'handwriting' &&
          (n.owner_id === GlobalState.userId() || n.visibility === 'shared'));
      } else {
        this.notes = all.filter((n: Note) => n.owner_id === GlobalState.userId() && n.kind === 'handwriting');
      }
      if (this.initialNoteId >= 0) {
        for (let i = 0; i < this.notes.length; i++) {
          if (this.notes[i].id === this.initialNoteId) {
            this.selectNote(i);
            return;
          }
        }
      }
      if (selectFirst && this.notes.length > 0) {
        this.selectNote(0);
      }
    } catch (e) {
      this.toast(`加载笔记失败：${(e as Error).message}`);
    }
  }

  private selectNote(index: number): void {
    this.selectedIndex = index;
    const n: Note | null = this.current();
    if (n !== null) {
      this.editorText = n.content;
      this.noteTitle = n.title;
      this.dirty = false;
      this.boardKey += 1;
    }
  }

  private selectNoteById(noteId: number): boolean {
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].id === noteId) {
        this.selectNote(i);
        return true;
      }
    }
    return false;
  }

  private async createNote(kind: string): Promise<void> {
    interface NoteBody {
      class_course_id: number;
      owner_id: number;
      title: string;
      kind: string;
      content: string;
    }

    const body: NoteBody = {
      class_course_id: GlobalState.courseId(),
      owner_id: GlobalState.userId(),
      title: '新手写笔记',
      kind: kind,
      content: ''
    };
    try {
      const created: Note = JSON.parse(await Api.post('/notes', body)) as Note;
      await this.loadNotes(false);
      if (!this.selectNoteById(created.id) && this.notes.length > 0) {
        this.selectNote(this.notes.length - 1);
      }
      this.toast('已创建');
    } catch (e) {
      this.toast(`创建失败：${(e as Error).message}`);
    }
  }

  private async persistNote(successText: string): Promise<void> {
    const n: Note | null = this.current();
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
      n.title = this.noteTitle;
      n.content = this.editorText;
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
    const n: Note | null = this.current();
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
      const deletedIndex: number = this.selectedIndex;
      await Api.remove(`/notes/${n.id}?user_id=${GlobalState.userId()}`);
      this.notes = this.notes.filter((item: Note) => item.id !== n.id);
      this.selectedIndex = -1;
      this.editorText = '';
      this.noteTitle = '';
      this.dirty = false;
      this.boardKey += 1;
      if (this.notes.length > 0) {
        this.selectNote(Math.min(deletedIndex, this.notes.length - 1));
      }
      this.toast('笔记已删除');
    } catch (e) {
      this.toast(`删除笔记失败：${(e as Error).message}`);
    }
  }

  private async toggleShare(): Promise<void> {
    const n: Note | null = this.current();
    if (n === null || !this.canEditCurrent()) {
      this.toast('当前笔记为只读');
      return;
    }
    this.sharing = true;
    try {
      if (n.visibility === 'private') {
        if (this.dirty) {
          await this.saveNote();
        }
        const updated: Note = JSON.parse(await Api.post(`/notes/${n.id}/share`)) as Note;
        this.notes.splice(this.selectedIndex, 1, updated);
        if (updated.kind === 'md') {
          if (updated.quality_status === 'accepted') {
            this.toast(`已共享，质量评估通过（${(updated.quality_score ?? 0).toFixed(1)} 分），已入知识库`);
          } else {
            this.toast('已共享，质量评估未通过，未入知识库');
          }
        } else {
          this.toast('已共享（手写笔记暂不入知识库）');
        }
      } else {
        const updated: Note = JSON.parse(await Api.post(`/notes/${n.id}/unshare`)) as Note;
        this.notes.splice(this.selectedIndex, 1, updated);
        this.toast('已设为私有');
      }
    } catch (e) {
      this.toast(`操作失败：${(e as Error).message}`);
    } finally {
      this.sharing = false;
    }
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
      Text('手写笔记')
        .fontSize(AppTheme.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.INK)
      Blank()
    }
    .width('100%')
    .height(44)
  }

  @Builder
  floatingToolbar() {
    Row({ space: AppTheme.SPACE_M }) {
      Text('‹')
        .fontSize(28)
        .fontColor(AppTheme.INK)
        .width(38)
        .height(38)
        .textAlign(TextAlign.Center)
        .borderRadius(19)
        .backgroundColor('rgba(255,255,255,0.72)')
        .onClick(() => {
          this.onBack();
        })

      TextInput({ text: this.noteTitle, placeholder: '笔记标题' })
        .fontSize(AppTheme.FONT_SUBTITLE)
        .layoutWeight(1)
        .height(40)
        .backgroundColor('rgba(255,255,255,0.58)')
        .borderRadius(20)
        .enabled(this.canEditCurrent())
        .onChange((v: string) => {
          this.noteTitle = v;
          this.dirty = true;
        })

      if (this.dirty) {
        Text('未保存')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.WARNING)
      }

      if (this.canEditCurrent()) {
        Button('重命名')
          .fontSize(AppTheme.FONT_BODY)
          .height(40)
          .backgroundColor('rgba(255,255,255,0.76)')
          .fontColor(AppTheme.TEXT_SECONDARY)
          .borderRadius(AppTheme.RADIUS_BTN)
          .onClick(() => {
            this.renameNote();
          })
        Button('保存')
          .fontSize(AppTheme.FONT_BODY)
          .height(40)
          .backgroundColor(AppTheme.PRIMARY)
          .borderRadius(999)
          .onClick(() => {
            this.saveNote();
          })
        Button('删除')
          .fontSize(AppTheme.FONT_BODY)
          .height(40)
          .backgroundColor(AppTheme.tagBg(AppTheme.DANGER))
          .fontColor(AppTheme.DANGER)
          .borderRadius(AppTheme.RADIUS_BTN)
          .onClick(() => {
            this.deleteCurrentNote();
          })
        Button(this.sharing ? '…' :
          (this.current() !== null && this.current()!.visibility === 'private' ? '共享' : '取消共享'))
          .fontSize(AppTheme.FONT_BODY)
          .height(40)
          .enabled(!this.sharing)
          .backgroundColor(this.current() !== null && this.current()!.visibility === 'private' ?
            AppTheme.SUCCESS : 'rgba(255,255,255,0.76)')
          .fontColor(this.current() !== null && this.current()!.visibility === 'private' ?
            '#FFFFFF' : AppTheme.TEXT_SECONDARY)
          .borderRadius(AppTheme.RADIUS_BTN)
          .onClick(() => {
            this.toggleShare();
          })
      } else {
        Text('只读')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(999)
          .backgroundColor('rgba(255,255,255,0.76)')
      }
    }
    .width('100%')
    .height(64)
    .padding({ left: AppTheme.SPACE_M, right: AppTheme.SPACE_M })
    .borderRadius(32)
    .backdropBlur(22)
    .backgroundColor('rgba(255,255,255,0.54)')
    .border({ width: 1, color: 'rgba(255,255,255,0.86)' })
    .shadow({ radius: 24, color: 'rgba(32,54,93,0.13)', offsetX: 0, offsetY: 8 })
    .margin({ left: AppTheme.SPACE_XL, right: AppTheme.SPACE_XL, top: AppTheme.SPACE_L })
  }

  @Builder
  handwritingBoardLayer() {
    Column() {
      if (this.boardKey % 2 === 0) {
        HandwritingBoard({
          readOnly: !this.canEditCurrent(),
          initialJson: this.editorText,
          onStrokesChanged: (json: string) => {
            this.editorText = json;
            this.dirty = true;
          }
        })
      } else {
        HandwritingBoard({
          readOnly: !this.canEditCurrent(),
          initialJson: this.editorText,
          onStrokesChanged: (json: string) => {
            this.editorText = json;
            this.dirty = true;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  emptyState() {
    Column({ space: AppTheme.SPACE_M }) {
      this.pageHeader()
      Column({ space: AppTheme.SPACE_M }) {
        Text('暂无可编辑的手写笔记')
          .fontSize(AppTheme.FONT_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT_SECONDARY)
        Text('请从个人笔记页面选择手写笔记，或点击 + 创建新手写笔记')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_TERTIARY)
        Button('返回个人笔记')
          .fontSize(AppTheme.FONT_BODY)
          .backgroundColor(AppTheme.PRIMARY)
          .borderRadius(999)
          .onClick(() => {
            this.onBack();
          })
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding(AppTheme.SPACE_XL)
    .backgroundColor(AppTheme.BG_PAGE)
  }

  @Builder
  handwritingWorkspace() {
    if (this.current() === null) {
      this.emptyState()
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        this.handwritingBoardLayer()
        this.floatingToolbar()
      }
      .width('100%')
      .height('100%')
    }
  }

  build() {
    Stack() {
      this.handwritingWorkspace()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG_PAGE)
  }
}
