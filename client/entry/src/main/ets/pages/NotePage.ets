import { TouchMotion } from '../common/TouchMotion';
import { LearningTheme as AppTheme } from '../common/LearningTheme';
import { MobileLayout } from '../common/MobileLayout';
import { GlobalState } from '../service/GlobalState';

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
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  onOpenClassNotes: () => void = () => {
  };
  onOpenPersonalNote: () => void = () => {
  };
  @State pageReady: boolean = false;
  @State pressedEntry: string = '';
  @State compact: boolean = false;
  private introTimer: number = -1;

  aboutToAppear(): void {
    this.pageReady = true;
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
    .stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'card'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'card')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
    .onClick(() => {
      this.pressedEntry = '';
      onTap();
    })
  }

  @Builder
  studyNoteEntry(title: string, icon: Resource, description: string, action: () => void) {
    Column({ space: 24 }) {
      Row() {
        Stack() { SymbolGlyph(icon).fontSize(32).fontColor([AppTheme.PRIMARY]) }.width(76).height(76)
          .borderRadius(24).backgroundColor(AppTheme.PRIMARY_LIGHT)
          .border({ width: 1, color: '#FFFFFF' }).shadow({ radius: 16, color: '#22436F9D', offsetY: 7 })
        Blank()
        SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(20).fontColor([AppTheme.PRIMARY])
      }.width('100%')
      Column({ space: 12 }) {
        Text(title).fontSize(28).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
        Text(description).fontSize(15).lineHeight(24).fontColor(AppTheme.TEXT_SECONDARY)
        Text('打开笔记  ›').fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppTheme.PRIMARY).margin({ top: 8 })
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').padding(32).constraintSize({ minHeight: 320 }).borderRadius(28)
      .linearGradient({ angle: 135, colors: [['#F2FFFFFF', 0], ['#BDE0EDF9', 1]] })
      .border({ width: 1, color: '#F0FFFFFF' }).shadow({ radius: 24, color: '#12436F9D', offsetY: 10 })
      .stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'card'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'card')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).onClick(action).accessibilityText(`打开${title}`)
  }

  @Builder
  mobileEntry(title: string, icon: Resource, tint: string, color: string, action: () => void) {
    Row({ space: 16 }) {
      Stack() { SymbolGlyph(icon).fontSize(24).fontColor([AppTheme.PRIMARY]) }.width(48).height(48)
        .backgroundColor(AppTheme.PRIMARY_LIGHT).borderRadius(12)
      Column({ space: 6 }) {
        Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
        Text(title === '班级笔记' ? '一起分享课堂中的收获' : '整理自己的学习思路')
          .fontSize(12).fontColor(AppTheme.TEXT_SECONDARY).maxLines(2)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([AppTheme.TEXT_TERTIARY])
    }.width('100%').constraintSize({ minHeight: 132 }).padding(22).borderRadius(24).backgroundColor(AppTheme.BG_CARD)
      .border({ width: 1, color: AppTheme.DIVIDER }).stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'card'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'card')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).onClick(action)
  }

  build() {
    Stack() {
      if (!GlobalState.isTeacher()) {
        Scroll() {
          Column({ space: 16 }) {
            Text('笔记').fontSize(26).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK).width('100%')
            Text(GlobalState.course?.name ?? '').fontSize(14).fontColor(AppTheme.TEXT_SECONDARY).width('100%')
            if (this.compact) {
              Column({ space: 16 }) {
                this.mobileEntry('班级笔记', $r('sys.symbol.person_2'), AppTheme.PRIMARY_LIGHT, AppTheme.PRIMARY, this.onOpenClassNotes)
                this.mobileEntry('个人笔记', $r('sys.symbol.doc_text'), AppTheme.PRIMARY_LIGHT, AppTheme.PRIMARY, this.onOpenPersonalNote)
              }.width('100%').padding({ top: 8 })
            } else {
              Row({ space: 24 }) {
                Column() { this.studyNoteEntry('班级笔记', $r('sys.symbol.person_2'), '把课堂上的不同理解放在一起，回看老师和同学分享的收获。', this.onOpenClassNotes) }.layoutWeight(1)
                Column() { this.studyNoteEntry('个人笔记', $r('sys.symbol.doc_text'), '用 AI 笔记或手写记录思考，逐步建立自己的知识脉络。', this.onOpenPersonalNote) }.layoutWeight(1)
              }.width('100%').padding({ top: 8 })
            }
            Row({ space: 16 }) {
              SymbolGlyph($r('sys.symbol.lightbulb')).fontSize(24).fontColor([AppTheme.PRIMARY])
              Column({ space: 6 }) {
                Text('让笔记和课堂连接').fontSize(17).fontWeight(FontWeight.Medium).fontColor(AppTheme.INK)
                Text('进入具体课次后，点击“本节笔记”，可以把思考记录在对应课堂下。')
                  .fontSize(13).lineHeight(22).fontColor(AppTheme.TEXT_SECONDARY)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%').padding(24).borderRadius(24).backgroundColor('#85FFFFFF')
          }.width('100%').constraintSize({ maxWidth: 1400 }).padding(this.compact ? 20 : 32)
        }.width('100%').height('100%').align(Alignment.Top)
      } else if (this.compact) {
        Column({ space: 16 }) {
          Text('笔记').fontSize(22).fontWeight(FontWeight.Bold).width('100%')
          if (MobileLayout.studentPhone()) {
            this.mobileEntry('班级笔记', $r('sys.symbol.person_2'), '#E0F6F0', '#00795C', this.onOpenClassNotes)
            this.mobileEntry('个人笔记', $r('sys.symbol.doc_text'), '#E8EFFF', '#305FC3', this.onOpenPersonalNote)
          } else {
          Button('班级笔记').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width('100%').height(72).fontColor(AppTheme.PRIMARY_DEEP)
            .backgroundColor(AppTheme.PRIMARY_LIGHT).onClick(() => { this.onOpenClassNotes(); })
          Button('个人笔记').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width('100%').height(72).backgroundColor(AppTheme.PRIMARY)
            .onClick(() => { this.onOpenPersonalNote(); })
          }
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
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(GlobalState.isTeacher() ? NOTE_BG : AppTheme.BG_PAGE)
    .onAreaChange((oldArea: Area, newArea: Area) => { this.compact = Number(newArea.width) < 900 || Number(newArea.height) < 600; })
  }
}
