import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppTheme } from '../common/AppTheme';
import { CourseSession, Note, Outline } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

/**
 * 课程主页：课程信息 + 统计 + 页面入口。
 */
@Component
export struct OverviewPage {
  @StorageLink('currentTab') currentTab: string = 'overview';
  @StorageLink('classSubPage') classSubPage: string = 'list';
  @StorageLink('noteSubPage') noteSubPage: string = 'hub';
  @State officialLessonCount: number = 0;
  @State classNoteCount: number = 0;
  @State personalNoteCount: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private async patchPublishedOfficialMeta(s: CourseSession): Promise<boolean> {
    try {
      const outline: Outline = JSON.parse(
        await Api.get(`/sessions/${s.id}/outline?user_id=${GlobalState.userId()}`)) as Outline;
      if (outline.status === 'published') {
        s.outline_kind = 'official';
        s.outline_status = 'published';
        return true;
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  private async load(): Promise<void> {
    try {
      const all: CourseSession[] = JSON.parse(
        await Api.get(`/sessions?class_course_id=${GlobalState.courseId()}&user_id=${GlobalState.userId()}`)) as CourseSession[];
      let officialCount: number = 0;
      for (let i = 0; i < all.length; i++) {
        const s: CourseSession = all[i];
        if (s.outline_kind === 'official' && s.outline_status === 'published') {
          officialCount++;
        } else {
          const published: boolean = await this.patchPublishedOfficialMeta(s);
          if (published) {
            officialCount++;
          }
        }
      }
      this.officialLessonCount = officialCount;
    } catch (e) {
      this.officialLessonCount = 0;
    }
    try {
      const notes: Note[] = JSON.parse(await Api.get(
        `/notes?class_course_id=${GlobalState.courseId()}&user_id=${GlobalState.userId()}`)) as Note[];
      this.classNoteCount = notes.filter((n: Note) => n.visibility === 'shared').length;
      this.personalNoteCount = notes.filter((n: Note) => n.owner_id === GlobalState.userId()).length;
    } catch (e) {
      this.classNoteCount = 0;
      this.personalNoteCount = 0;
    }
  }

  private copyInvite(): void {
    if (GlobalState.course === null) {
      return;
    }
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, GlobalState.course.invite_code);
    pasteboard.getSystemPasteboard().setData(data);
    this.toast('邀请码已复制');
  }

  private openClassPage(): void {
    this.classSubPage = 'list';
    this.currentTab = 'class';
    GlobalState.updateSnapshot('class');
  }

  private openAiPage(): void {
    if (GlobalState.isTeacher()) {
      this.toast('AI 页面仅学生端开放');
      return;
    }
    this.currentTab = 'course_ai';
    GlobalState.updateSnapshot('course_ai');
  }

  private openNotesPage(): void {
    this.noteSubPage = 'hub';
    this.currentTab = 'notes';
    GlobalState.updateSnapshot('notes');
  }

  @Builder
  statCard(num: string, label: string, accent: string) {
    Column({ space: AppTheme.SPACE_XS }) {
      Text(num)
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(accent)
      Text(label)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_TERTIARY)
    }
    .layoutWeight(1)
    .padding(AppTheme.SPACE_L)
    .height(116)
    .borderRadius(AppTheme.RADIUS_CARD)
    .backgroundColor(AppTheme.BG_CARD)
    .alignItems(HorizontalAlign.Start)
    .shadow({ radius: 16, color: 'rgba(17,17,17,0.04)', offsetX: 0, offsetY: 4 })
  }

  @Builder
  entryCard(title: string, desc: string, mark: string, accent: string, bg: string, onTap: () => void) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(24)
        .backgroundColor(AppTheme.BG_CARD)
      Column()
        .width(118)
        .height(118)
        .borderRadius(59)
        .backgroundColor(bg)
        .align(Alignment.TopEnd)
        .margin({ top: -34, right: -28 })
      Column({ space: AppTheme.SPACE_M }) {
        Text(mark)
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(accent)
          .width(56)
          .height(56)
          .textAlign(TextAlign.Center)
          .borderRadius(18)
          .backgroundColor(bg)
        Blank()
        Text(title)
          .fontSize(AppTheme.FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.INK)
        Text(desc)
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .maxLines(2)
        Text('进入')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(accent)
      }
      .width('100%')
      .height('100%')
      .padding(AppTheme.SPACE_XL)
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .height(230)
    .clip(true)
    .shadow({ radius: 20, color: 'rgba(17,17,17,0.06)', offsetX: 0, offsetY: 6 })
    .onClick(() => {
      onTap();
    })
  }

  build() {
    Column({ space: 28 }) {
      // 头部
      Row({ space: AppTheme.SPACE_M }) {
        Column({ space: AppTheme.SPACE_XS }) {
          Text(GlobalState.course === null ? '' : GlobalState.course.name)
            .fontSize(46)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(GlobalState.course === null ? '' :
            `${GlobalState.course.class_name} · ${GlobalState.course.teacher_name ?? ''}`)
            .fontSize(AppTheme.FONT_BODY)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
        Text(`邀请码 ${GlobalState.course === null ? '' : GlobalState.course.invite_code} ⧉`)
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.PRIMARY)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(999)
          .backgroundColor(AppTheme.PRIMARY_LIGHT)
          .onClick(() => {
            this.copyInvite();
          })
      }
      .width('100%')

      // 统计
      Row({ space: AppTheme.SPACE_L }) {
        this.statCard(`${this.officialLessonCount}`, '官方发布课时', AppTheme.INK)
        this.statCard(`${this.classNoteCount}`, '班级笔记', AppTheme.PRIMARY)
        this.statCard(`${this.personalNoteCount}`, '个人笔记', AppTheme.SUCCESS)
      }
      .width('100%')

      Row({ space: AppTheme.SPACE_L }) {
        this.entryCard('课程', '课堂记录、官方课时与录音成果', '课', AppTheme.INK,
          'rgba(226,239,255,0.92)', (): void => {
            this.openClassPage();
          })
        this.entryCard('AI', '基于课程知识库的问答助手', 'AI', AppTheme.PRIMARY,
          'rgba(224,240,255,0.92)', (): void => {
            this.openAiPage();
          })
        this.entryCard('笔记', '班级笔记与个人笔记', '笔', AppTheme.SUCCESS,
          'rgba(224,248,238,0.92)', (): void => {
            this.openNotesPage();
          })
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .height('100%')
    .padding(AppTheme.SPACE_XXL)
    .backgroundColor(AppTheme.BG_PAGE)
  }
}
