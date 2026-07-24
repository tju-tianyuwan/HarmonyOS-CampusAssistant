import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { Note } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

@Component
export struct ClassNotesPage {
  onBack: () => void = () => {
  };
  onOpenAiNote: (noteId: number) => void = () => {
  };
  onOpenHandwritingNote: (noteId: number) => void = () => {
  };
  @State notes: Note[] = [];

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
      this.notes = all.filter((n: Note) => n.visibility === 'shared');
    } catch (e) {
      this.toast(`加载班级笔记失败：${(e as Error).message}`);
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
      Text('班级笔记')
        .fontSize(AppTheme.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.INK)
      Blank()
      Text(`${this.notes.length} 篇共享`)
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
    Column({ space: AppTheme.SPACE_M }) {
      Row() {
        Text(n.kind === 'md' ? 'MD' : '手写')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(n.kind === 'md' ? AppTheme.PRIMARY : AppTheme.WARNING)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(999)
          .backgroundColor(AppTheme.tagBg(n.kind === 'md' ? AppTheme.PRIMARY : AppTheme.WARNING))
        Blank()
        Text(n.quality_status === 'accepted' ? '已入库' : '共享')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(n.quality_status === 'accepted' ? AppTheme.SUCCESS : AppTheme.TEXT_TERTIARY)
      }
      .width('100%')

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
      Text(n.updated_at)
        .fontSize(10)
        .fontColor(AppTheme.TEXT_TERTIARY)
    }
    .width(260)
    .height(190)
    .padding(AppTheme.SPACE_L)
    .borderRadius(18)
    .backgroundColor(AppTheme.BG_CARD)
    .shadow({ radius: 18, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 6 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      if (n.kind === 'md') {
        this.onOpenAiNote(n.id);
      } else {
        this.onOpenHandwritingNote(n.id);
      }
    })
  }

  build() {
    Column({ space: AppTheme.SPACE_L }) {
      this.pageHeader()
      if (this.notes.length === 0) {
        Column({ space: AppTheme.SPACE_S }) {
          Text('暂无班级共享笔记')
            .fontSize(AppTheme.FONT_SUBTITLE)
            .fontColor(AppTheme.TEXT_SECONDARY)
          Text('同学或老师共享后会显示在这里')
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
  }
}
