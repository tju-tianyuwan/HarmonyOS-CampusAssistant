import { AppTheme } from '../common/AppTheme';

@Component
export struct NotePage {
  onOpenClassNotes: () => void = () => {
  };
  onOpenPersonalNote: () => void = () => {
  };

  @Builder
  noteEntryCard(title: string, desc: string, mark: string, accent: string, onTap: () => void) {
    Column({ space: AppTheme.SPACE_L }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(92)
          .height(92)
          .borderRadius(28)
          .backgroundColor(AppTheme.tagBg(accent))
        Text(mark)
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor(accent)
      }

      Text(title)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.INK)
      Text(desc)
        .fontSize(AppTheme.FONT_BODY)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .maxLines(2)
      Text('进入')
        .fontSize(AppTheme.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .padding({ left: 22, right: 22, top: 8, bottom: 8 })
        .borderRadius(999)
        .backgroundColor(accent)
        .margin({ top: AppTheme.SPACE_S })
    }
    .layoutWeight(1)
    .height(300)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(AppTheme.SPACE_XL)
    .borderRadius(24)
    .backgroundColor(AppTheme.BG_CARD)
    .shadow({ radius: 28, color: 'rgba(0,0,0,0.07)', offsetX: 0, offsetY: 8 })
    .onClick(() => {
      onTap();
    })
  }

  build() {
    Column({ space: AppTheme.SPACE_XL }) {
      Column({ space: AppTheme.SPACE_S }) {
        Text('笔记')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.INK)
        Text('选择本课程的笔记工作方式')
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_SECONDARY)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row({ space: AppTheme.SPACE_XL }) {
        this.noteEntryCard('班级笔记', '查看本课程中同学和老师共享的笔记卡片。', '班', AppTheme.PRIMARY,
          (): void => {
            this.onOpenClassNotes();
          })
        this.noteEntryCard('个人笔记', '管理自己的课程笔记，并创建 AI 笔记或手写笔记。', '个', '#4C8DFF',
          (): void => {
            this.onOpenPersonalNote();
          })
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding(AppTheme.SPACE_XXL)
    .backgroundColor(AppTheme.BG_PAGE)
  }
}
