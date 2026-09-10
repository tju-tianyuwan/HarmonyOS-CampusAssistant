import { AppTheme } from '../common/AppTheme';

const NOTE_BG: string = '#F2F7F6';
const NOTE_PANEL: string = '#FFFFFF';
const NOTE_SOFT: string = '#F5FFFB';
const NOTE_BLUE: string = '#3F7DFF';
const NOTE_AMBER: string = '#FFB84D';
const NOTE_VIOLET: string = '#7A63F3';
const NOTE_GLASS: string = 'rgba(255,255,255,0.90)';
const NOTE_BORDER: string = 'rgba(255,255,255,0.92)';

@Component
export struct NotePage {
  onOpenClassNotes: () => void = () => {
  };
  onOpenPersonalNote: () => void = () => {
  };
  @State pageReady: boolean = false;
  @State pressedEntry: string = '';
  @State compact: boolean = false;
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

  @Builder
  pageAtmosphere() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 34,
          colors: [
            ['#F8FCFA', 0],
            [NOTE_BG, 0.54],
            ['#EEF3FF', 1]
          ]
        })
      Column()
        .width(520)
        .height(560)
        .borderRadius(70)
        .rotate({ angle: -18 })
        .linearGradient({
          angle: 112,
          colors: [
            ['rgba(5,206,145,0.16)', 0],
            ['rgba(18,191,232,0.09)', 0.66],
            ['rgba(255,255,255,0.02)', 1]
          ]
        })
        .position({ x: -170, y: -120 })
      Column()
        .width(640)
        .height(380)
        .borderRadius(58)
        .rotate({ angle: 11 })
        .linearGradient({
          angle: 72,
          colors: [
            ['rgba(122,99,243,0.12)', 0],
            ['rgba(63,125,255,0.08)', 0.62],
            ['rgba(255,255,255,0.02)', 1]
          ]
        })
        .position({ x: 980, y: 260 })
      Column()
        .width('100%')
        .height(1)
        .backgroundColor('rgba(255,255,255,0.74)')
        .position({ x: 0, y: 222 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  heroBand() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(34)
        .linearGradient({
          angle: 120,
          colors: [
            [NOTE_PANEL, 0],
            [NOTE_SOFT, 0.58],
            ['#EEF3FF', 1]
          ]
        })
      Column()
        .width(520)
        .height(220)
        .borderRadius(46)
        .rotate({ angle: -10 })
        .linearGradient({
          angle: 70,
          colors: [
            ['rgba(5,206,145,0.22)', 0],
            ['rgba(18,191,232,0.10)', 0.62],
            ['rgba(255,255,255,0.02)', 1]
          ]
        })
        .position({ x: -80, y: -62 })
      Column()
        .width(380)
        .height(220)
        .borderRadius(42)
        .rotate({ angle: 12 })
        .backgroundColor('rgba(63,125,255,0.13)')
        .position({ x: 890, y: -42 })
      Row() {
        Column({ space: AppTheme.SPACE_M }) {
          Row({ space: 8 }) {
            Text('NOTE STUDIO')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor('#121818')
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(999)
              .backgroundColor(AppTheme.PRIMARY)
            Text('课程资产')
              .fontSize(11)
              .fontColor('rgba(18,24,24,0.58)')
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(999)
              .backgroundColor('rgba(18,24,24,0.06)')
          }
          Text('笔记')
            .fontSize(46)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK)
          Text('把班级共创、个人沉淀和 AI 结构化记录放在同一个工作台。')
            .fontSize(AppTheme.FONT_BODY)
            .fontColor('rgba(18,24,24,0.56)')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(132)
            .height(162)
            .borderRadius(18)
            .rotate({ angle: -8 })
            .backgroundColor('rgba(255,255,255,0.90)')
          Column()
            .width(118)
            .height(150)
            .borderRadius(18)
            .rotate({ angle: 9 })
            .backgroundColor('rgba(255,255,255,0.72)')
          Column({ space: 9 }) {
            Column()
              .width(78)
              .height(8)
              .borderRadius(4)
              .backgroundColor(AppTheme.PRIMARY)
            Column()
              .width(102)
              .height(7)
              .borderRadius(4)
              .backgroundColor('rgba(18,24,24,0.18)')
            Column()
              .width(68)
              .height(7)
              .borderRadius(4)
              .backgroundColor('rgba(18,24,24,0.12)')
          }
          .width(104)
          .height(118)
          .justifyContent(FlexAlign.Center)
        }
        .width(220)
        .height(180)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 38, right: 34 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(236)
    .clip(true)
    .borderRadius(34)
    .border({ width: 1.2, color: NOTE_BORDER })
    .shadow({ radius: 30, color: 'rgba(31,62,68,0.12)', offsetX: 0, offsetY: 14 })
  }

  @Builder
  entryMark(mark: string, accent: string, secondary: string) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(154)
        .height(154)
        .borderRadius(42)
        .rotate({ angle: -10 })
        .backgroundColor(AppTheme.tagBg(accent))
      Column()
        .width(102)
        .height(102)
        .borderRadius(30)
        .rotate({ angle: 9 })
        .backgroundColor(AppTheme.tagBg(secondary))
      Text(mark)
        .fontSize(56)
        .fontWeight(FontWeight.Bold)
        .fontColor(accent)
    }
    .width(190)
    .height(174)
  }

  @Builder
  featureLine(text: string, color: string) {
    Row({ space: 8 }) {
      Column()
        .width(7)
        .height(7)
        .borderRadius(4)
        .backgroundColor(color)
      Text(text)
        .fontSize(15)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .lineHeight(22)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  @Builder
  noteEntryCard(key: string, title: string, desc: string, mark: string, accent: string, secondary: string,
    onTap: () => void) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(30)
        .backgroundColor(NOTE_GLASS)
      Row() {
        Column({ space: 28 }) {
          Row({ space: 8 }) {
            Column()
              .width(8)
              .height(8)
              .borderRadius(4)
              .backgroundColor(accent)
            Text(key === 'class' ? '班级共创' : '私人工作台')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(accent)
          }
          Text(title)
            .fontSize(48)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK)
          Text(desc)
            .fontSize(19)
            .fontColor(AppTheme.TEXT_SECONDARY)
            .lineHeight(31)
            .maxLines(4)
            .constraintSize({ maxWidth: 520 })
          Column({ space: 14 }) {
            this.featureLine(key === 'class' ? '共享笔记、课堂灵感和老师资料集中浏览' : 'AI 笔记、手写笔记和个人沉淀统一管理', accent)
            this.featureLine(key === 'class' ? '优质共享内容可进入课程记忆' : '保留私人学习脉络，可按需共享', secondary)
          }
          Row({ space: 8 }) {
            Text('进入')
              .fontSize(AppTheme.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
            Text('→')
              .fontSize(AppTheme.FONT_BODY)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
          }
          .height(48)
          .padding({ left: 24, right: 24 })
          .borderRadius(999)
          .backgroundColor(accent)
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)

        this.entryMark(mark, accent, secondary)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 30, right: 28, top: 26, bottom: 26 })
      Column()
        .width(112)
        .height(8)
        .borderRadius(4)
        .backgroundColor(accent)
        .opacity(0.18)
        .position({ x: 34, y: 38 })
    }
    .layoutWeight(1)
    .height('100%')
    .clip(true)
    .borderRadius(30)
    .border({ width: 1.2, color: NOTE_BORDER })
    .shadow({
      radius: this.pressedEntry === key ? 18 : 32,
      color: this.pressedEntry === key ? 'rgba(31,62,68,0.08)' : 'rgba(24,58,74,0.15)',
      offsetX: 0,
      offsetY: this.pressedEntry === key ? 8 : 14
    })
    .translate({ x: 0, y: this.pressedEntry === key ? 5 : 0 })
    .scale({
      x: this.pressedEntry === key ? 0.976 : 1,
      y: this.pressedEntry === key ? 0.976 : 1
    })
    .animation({ duration: this.pressedEntry === key ? 90 : 260, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedEntry = key;
      } else if (event.type === TouchType.Up) {
        this.pressedEntry = '';
      }
    })
    .onClick(() => {
      this.pressedEntry = '';
      onTap();
    })
  }

  build() {
    Stack() {
      if (this.compact) {
        Column({ space: 16 }) {
          Text('笔记').fontSize(22).fontWeight(FontWeight.Bold).width('100%')
          Button('班级笔记').width('100%').height(72).fontColor(AppTheme.PRIMARY_DEEP)
            .backgroundColor(AppTheme.PRIMARY_LIGHT).onClick(() => { this.onOpenClassNotes(); })
          Button('个人笔记').width('100%').height(72).backgroundColor(AppTheme.PRIMARY)
            .onClick(() => { this.onOpenPersonalNote(); })
        }.padding(20).width('100%').height('100%')
      } else {
      this.pageAtmosphere()
      Column({ space: AppTheme.SPACE_L }) {
        this.heroBand()
        Row({ space: AppTheme.SPACE_L }) {
          this.noteEntryCard('class', '班级笔记', '查看本课程中同学和老师共享的笔记卡片，让共创内容进入课程记忆。',
            '班', AppTheme.PRIMARY, NOTE_AMBER, (): void => {
              this.onOpenClassNotes();
            })
          this.noteEntryCard('personal', '个人笔记', '管理自己的课程笔记，并创建 AI 笔记或手写笔记，保留个人学习脉络。',
            '个', NOTE_BLUE, NOTE_VIOLET, (): void => {
              this.onOpenPersonalNote();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding({ left: AppTheme.SPACE_XXL, right: AppTheme.SPACE_XXL, top: 28, bottom: AppTheme.SPACE_XXL })
      .opacity(this.pageReady ? 1 : 0)
      .translate({ x: 0, y: this.pageReady ? 0 : 24 })
      .scale({ x: this.pageReady ? 1 : 0.986, y: this.pageReady ? 1 : 0.986 })
      .animation({ duration: 360, curve: Curve.EaseOut })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(NOTE_BG)
    .onAreaChange((oldArea: Area, newArea: Area) => { this.compact = Number(newArea.width) < 900 || Number(newArea.height) < 600; })
  }
}
