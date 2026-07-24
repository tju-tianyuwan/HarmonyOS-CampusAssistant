import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { Note } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

@Component
export struct PersonalNotePage {
  onBack: () => void = () => {
  };
  onCreateAiNote: () => void = () => {
  };
  onCreateHandwritingNote: () => void = () => {
  };
  onOpenAiNote: (noteId: number) => void = () => {
  };
  onOpenHandwritingNote: (noteId: number) => void = () => {
  };
  @State notes: Note[] = [];
  @State showCreateOptions: boolean = false;

  aboutToAppear(): void {
    this.loadNotes();
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private async loadNotes(): Promise<void> {
    try {
      const all: Note[] = JSON.parse(await Api.get(
        `/notes?class_course_id=${GlobalState.courseId()}&user_id=${GlobalState.userId()}`)) as Note[];
      this.notes = all.filter((n: Note) => n.owner_id === GlobalState.userId());
    } catch (e) {
      this.toast(`加载个人笔记失败：${(e as Error).message}`);
    }
  }

  private noteExcerpt(n: Note): string {
    if (n.kind !== 'md') {
      return n.content.trim() === '' ? '暂无手写内容' : '手写笔迹已保存';
    }
    if (n.content.trim() === '') {
      return '暂无 Markdown 内容';
    }
    return n.content.trim();
  }

  private openNote(n: Note): void {
    if (n.kind === 'md') {
      this.onOpenAiNote(n.id);
    } else {
      this.onOpenHandwritingNote(n.id);
    }
  }

  private async deleteNote(n: Note): Promise<void> {
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
      await Api.remove(`/notes/${n.id}?user_id=${GlobalState.userId()}`);
      this.notes = this.notes.filter((item: Note) => item.id !== n.id);
      this.toast('笔记已删除');
    } catch (e) {
      this.toast(`删除笔记失败：${(e as Error).message}`);
    }
  }

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
      Text('个人笔记')
        .fontSize(AppTheme.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.INK)
      Blank()
      Text(`${this.notes.length} 篇`)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .padding({ left: 12, right: 12, top: 5, bottom: 5 })
        .borderRadius(999)
        .backgroundColor(AppTheme.BG_CARD)
    }
    .width('100%')
    .height(44)
  }

  @Builder
  noteCard(n: Note) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: AppTheme.SPACE_M }) {
        Row() {
          Text(n.kind === 'md' ? 'AI 笔记' : '手写')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(n.kind === 'md' ? AppTheme.PRIMARY : '#4C8DFF')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(999)
            .backgroundColor(AppTheme.tagBg(n.kind === 'md' ? AppTheme.PRIMARY : '#4C8DFF'))
          Blank()
          Text(n.visibility === 'shared' ? '共享' : '私有')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(n.visibility === 'shared' ? AppTheme.SUCCESS : AppTheme.TEXT_TERTIARY)
        }
        .width('100%')
        .padding({ right: 42 })

        Text(n.title)
          .fontSize(AppTheme.FONT_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.noteExcerpt(n))
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        Row() {
          Text(n.updated_at)
            .fontSize(10)
            .fontColor(AppTheme.TEXT_TERTIARY)
          Blank()
          Text('打开 ›')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(n.kind === 'md' ? AppTheme.PRIMARY : '#4C8DFF')
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding(AppTheme.SPACE_L)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.openNote(n);
      })

      Text('删除')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.DANGER)
        .margin({ top: AppTheme.SPACE_L, right: AppTheme.SPACE_L })
        .onClick(() => {
          this.deleteNote(n);
        })
    }
    .width(260)
    .height(190)
    .borderRadius(18)
    .backgroundColor(AppTheme.BG_CARD)
    .shadow({ radius: 18, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 6 })
  }

  @Builder
  createOption(title: string, desc: string, accent: string, onTap: () => void) {
    Column({ space: AppTheme.SPACE_S }) {
      Text(title)
        .fontSize(AppTheme.FONT_SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.INK)
      Text(desc)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .maxLines(2)
      Text('选择')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(accent)
        .margin({ top: AppTheme.SPACE_S })
    }
    .layoutWeight(1)
    .height(130)
    .padding(AppTheme.SPACE_L)
    .borderRadius(18)
    .backgroundColor(AppTheme.BG_CARD)
    .border({ width: 1, color: AppTheme.tagBg(accent) })
    .onClick(() => {
      this.showCreateOptions = false;
      onTap();
    })
  }

  @Builder
  createOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(20,34,72,0.24)')
        .backdropBlur(18)
        .onClick(() => {
          this.showCreateOptions = false;
        })
      Column({ space: AppTheme.SPACE_L }) {
        Text('创建新笔记')
          .fontSize(AppTheme.FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.INK)
        Row({ space: AppTheme.SPACE_L }) {
          this.createOption('AI 笔记', '进入 Markdown 与 AI 辅助笔记工作台。', AppTheme.PRIMARY, (): void => {
            this.onCreateAiNote();
          })
          this.createOption('手写笔记', '进入手写画板与手写笔记管理。', '#4C8DFF', (): void => {
            this.onCreateHandwritingNote();
          })
        }
        .width('100%')
      }
      .width(520)
      .padding(AppTheme.SPACE_XL)
      .borderRadius(24)
      .backdropBlur(24)
      .backgroundColor('rgba(255,255,255,0.82)')
      .border({ width: 1.2, color: 'rgba(255,255,255,0.94)' })
      .shadow({ radius: 36, color: 'rgba(56,99,240,0.22)', offsetX: 0, offsetY: 16 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  fab() {
    Text('+')
      .fontSize(38)
      .fontWeight(FontWeight.Medium)
      .fontColor('#FFFFFF')
      .width(72)
      .height(72)
      .textAlign(TextAlign.Center)
      .borderRadius(36)
      .backgroundColor(AppTheme.PRIMARY)
      .shadow({ radius: 24, color: 'rgba(5,206,145,0.34)', offsetX: 0, offsetY: 10 })
      .margin({ right: AppTheme.SPACE_XL, bottom: AppTheme.SPACE_XL })
      .onClick(() => {
        this.showCreateOptions = true;
      })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: AppTheme.SPACE_L }) {
        this.pageHeader()
        if (this.notes.length === 0) {
          Column({ space: AppTheme.SPACE_S }) {
            Text('还没有个人笔记')
              .fontSize(AppTheme.FONT_SUBTITLE)
              .fontColor(AppTheme.TEXT_SECONDARY)
            Text('点击右下角 + 创建 AI 笔记或手写笔记')
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_TERTIARY)
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll() {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.notes, (n: Note) => {
                Column() {
                  this.noteCard(n)
                }
                .margin({ right: AppTheme.SPACE_L, bottom: AppTheme.SPACE_L })
              }, (n: Note) => `${n.id}`)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .padding(AppTheme.SPACE_XL)
      .backgroundColor(AppTheme.BG_PAGE)

      this.fab()

      if (this.showCreateOptions) {
        this.createOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
