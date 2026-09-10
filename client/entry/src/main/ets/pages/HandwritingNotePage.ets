import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { HandwritingBoard } from '../common/components/HandwritingBoard';
import { Note } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';
import { common } from '@kit.AbilityKit';
import { NoteDraftStore } from '../service/NoteDraftStore';
import { transferService, TransferNote } from '../service/collab/TransferService';

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
  @State saving: boolean = false;
  @State compact: boolean = false;
  private drafts: NoteDraftStore | null = null;
  private leaving: boolean = false;
  private active: boolean = true;
  /** 手写画板重建开关：切换笔记时强制重建组件加载新笔迹 */
  @State boardKey: number = 0;

  aboutToAppear(): void {
    this.active = true;
    try {
      this.drafts = new NoteDraftStore((getContext(this) as common.UIAbilityContext).filesDir, Api.BASE_URL, GlobalState.userId());
    } catch (e) { this.toast('草稿存储不可用，请及时保存'); }
    GlobalState.beforeLeaveNote = (done: () => void) => { this.leave(done); };
    transferService.setNoteProvider((): TransferNote | null => this.current() === null ? null :
      { title: this.noteTitle, kind: 'handwriting', content: this.editorText });
    if (this.createOnAppear) {
      this.createNote('handwriting');
    } else {
      this.loadNotes(true);
    }
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  aboutToDisappear(): void {
    if (this.dirty) { this.cacheDraft(); }
    this.active = false;
    GlobalState.beforeLeaveNote = null;
    transferService.setNoteProvider(null);
  }

  private cacheDraft(): boolean {
    const note = this.current();
    if (note === null || !this.canEditCurrent() || this.drafts === null) { return false; }
    try { this.drafts.save(note.id, { title: this.noteTitle, content: this.editorText }); return true; }
    catch (e) { this.toast('草稿写入失败，请保存后离开'); return false; }
  }

  private async leave(done: () => void): Promise<void> {
    if (this.leaving || this.saving || this.sharing) { return; }
    if (!this.dirty) { done(); return; }
    this.leaving = true;
    try {
      const cached = this.cacheDraft();
      const result = await promptAction.showDialog({ title: '笔记尚未保存', message: cached ? '保存到服务器后离开，或保留本机草稿？' : '草稿写入失败，请保存到服务器后离开',
        buttons: [{ text: '取消', color: AppTheme.TEXT_SECONDARY },
          { text: '保留草稿离开', color: AppTheme.TEXT_SECONDARY }, { text: '保存并离开', color: AppTheme.PRIMARY }] });
      if (result.index === 1 && cached) { done(); }
      if (result.index === 2 && await this.persistNote('已保存') && !this.dirty) { done(); }
    } finally { this.leaving = false; }
  }

  private async restoreDraft(id: number): Promise<void> {
    try {
      const draft = this.drafts?.load(id);
      if (!draft || (draft.content === this.editorText && draft.title === this.noteTitle)) { return; }
      const result = await promptAction.showDialog({ title: '发现本机草稿', message: '恢复上次尚未保存的修改？',
        buttons: [{ text: '使用服务器版本', color: AppTheme.TEXT_SECONDARY }, { text: '恢复草稿', color: AppTheme.PRIMARY }] });
      if (!this.active || this.current()?.id !== id) { return; }
      if (result.index === 1) {
        this.editorText = draft.content; this.noteTitle = draft.title; this.dirty = true; this.boardKey++;
      } else if (result.index === 0) { this.drafts?.remove(id); }
    } catch (e) { this.toast('草稿读取失败，已保留草稿文件'); }
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
      if (this.canEditCurrent()) { this.restoreDraft(n.id); }
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

  private async persistNote(successText: string): Promise<boolean> {
    if (this.saving) { return false; }
    const n: Note | null = this.current();
    if (n === null || !this.canEditCurrent()) {
      this.toast('当前笔记为只读');
      return false;
    }
    interface UpdateBody {
      title: string;
      content: string;
    }

    const body: UpdateBody = { title: this.noteTitle, content: this.editorText };
    this.saving = true;
    try {
      await Api.put(`/notes/${n.id}`, body);
      n.title = body.title;
      n.content = body.content;
      if (this.current()?.id === n.id) {
        this.dirty = this.noteTitle !== body.title || this.editorText !== body.content;
        if (!this.dirty) { this.drafts?.remove(n.id); } else { this.cacheDraft(); }
      }
      this.toast(successText);
      return true;
    } catch (e) {
      this.toast(`保存失败：${(e as Error).message}`);
      return false;
    } finally {
      this.saving = false;
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
      this.drafts?.remove(n.id);
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
          if (!await this.persistNote('已保存')) { return; }
          if (this.dirty) { this.toast('笔迹有新修改，请保存后再共享'); return; }
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
          this.leave(this.onBack);
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
    if (this.compact) {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Button('返回').backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).onClick(() => { this.leave(this.onBack); })
          TextInput({ text: this.noteTitle, placeholder: '笔记标题' }).layoutWeight(1).enabled(this.canEditCurrent())
            .onChange((value: string) => { if (value !== this.noteTitle) { this.noteTitle = value; this.dirty = true; this.cacheDraft(); } })
        }.width('100%')
        Row({ space: 8 }) {
          if (this.dirty) { Text('未保存').fontSize(12).fontColor(AppTheme.WARNING) }
          Blank()
          if (this.canEditCurrent()) {
            Button('保存').backgroundColor(AppTheme.PRIMARY).enabled(!this.saving && !this.sharing).onClick(() => { this.saveNote(); })
            Button('删除').fontColor(AppTheme.DANGER).backgroundColor(Color.Transparent).enabled(!this.saving && !this.sharing).onClick(() => { this.deleteCurrentNote(); })
            Button(this.current()?.visibility === 'private' ? '共享' : '取消共享').backgroundColor(AppTheme.PRIMARY_LIGHT)
              .fontColor(AppTheme.PRIMARY_DEEP).enabled(!this.saving && !this.sharing).onClick(() => { this.toggleShare(); })
          } else { Text('只读').fontSize(13) }
        }.width('100%')
      }.width('100%').padding(8).backgroundColor(AppTheme.BG_CARD)
    } else {
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
          this.leave(this.onBack);
        })

      TextInput({ text: this.noteTitle, placeholder: '笔记标题' })
        .fontSize(AppTheme.FONT_SUBTITLE)
        .layoutWeight(1)
        .height(40)
        .backgroundColor('rgba(255,255,255,0.58)')
        .borderRadius(20)
        .enabled(this.canEditCurrent())
        .onChange((v: string) => {
          if (v === this.noteTitle) { return; }
          this.noteTitle = v;
          this.dirty = true;
          this.cacheDraft();
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
          .enabled(!this.saving && !this.sharing)
          .fontSize(AppTheme.FONT_BODY)
          .height(40)
          .backgroundColor(AppTheme.PRIMARY)
          .borderRadius(999)
          .onClick(() => {
            this.saveNote();
          })
        Button('删除')
          .enabled(!this.saving && !this.sharing)
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
          .enabled(!this.sharing && !this.saving)
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
    .height(64)
    .padding({ left: AppTheme.SPACE_M, right: AppTheme.SPACE_M })
    .borderRadius(32)
    .backdropBlur(22)
    .backgroundColor('rgba(255,255,255,0.54)')
    .border({ width: 1, color: 'rgba(255,255,255,0.86)' })
    .shadow({ radius: 24, color: 'rgba(32,54,93,0.13)', offsetX: 0, offsetY: 8 })
    .width('calc(100% - 48vp)')
    .margin({ left: AppTheme.SPACE_XL, right: AppTheme.SPACE_XL, top: AppTheme.SPACE_L })
    }
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
            this.cacheDraft();
          }
        })
      } else {
        HandwritingBoard({
          readOnly: !this.canEditCurrent(),
          initialJson: this.editorText,
          onStrokesChanged: (json: string) => {
            this.editorText = json;
            this.dirty = true;
            this.cacheDraft();
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
      Column() {
        if (this.compact) { this.floatingToolbar() }
        Stack({ alignContent: Alignment.TopStart }) {
        this.handwritingBoardLayer()
        if (!this.compact) { this.floatingToolbar() }
        }.width('100%').layoutWeight(1)
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
    .onAreaChange((oldArea: Area, newArea: Area) => { this.compact = Number(newArea.width) < 760; })
  }
}
