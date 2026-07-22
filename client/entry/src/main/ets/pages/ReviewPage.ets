import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { AppCard } from '../common/components/AppCard';
import { Outline } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

/**
 * P6 教师审核：待审提纲列表 | 编辑预览 + 发布/退回。
 * 发布后提纲向量化写入本课程集合知识库。
 */
@Component
export struct ReviewPage {
  @State pendingList: Outline[] = [];
  @State selectedIndex: number = -1;
  @State editText: string = '';
  @State dirty: boolean = false;
  @State busy: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private current(): Outline | null {
    return this.selectedIndex < 0 || this.selectedIndex >= this.pendingList.length ?
      null : this.pendingList[this.selectedIndex];
  }

  private async load(): Promise<void> {
    try {
      this.pendingList = JSON.parse(await Api.get(
        `/sessions/outlines/pending?class_course_id=${GlobalState.courseId()}`)) as Outline[];
      if (this.pendingList.length > 0) {
        this.select(0);
      } else {
        this.selectedIndex = -1;
        this.editText = '';
      }
    } catch (e) {
      this.toast(`加载失败：${(e as Error).message}`);
    }
  }

  private select(index: number): void {
    this.selectedIndex = index;
    const o: Outline | null = this.current();
    this.editText = o === null ? '' : o.markdown;
    this.dirty = false;
  }

  private async saveEdit(): Promise<void> {
    const o: Outline | null = this.current();
    if (o === null) {
      return;
    }
    interface UpdateBody {
      markdown: string;
    }

    const body: UpdateBody = { markdown: this.editText };
    try {
      await Api.put(`/sessions/${o.session_id}/outline`, body);
      o.markdown = this.editText;
      this.dirty = false;
      this.toast('修改已保存');
    } catch (e) {
      this.toast(`保存失败：${(e as Error).message}`);
    }
  }

  private async review(action: string): Promise<void> {
    const o: Outline | null = this.current();
    if (o === null) {
      return;
    }
    this.busy = true;
    try {
      if (this.dirty) {
        await this.saveEdit();
      }
      interface ReviewBody {
        user_id: number;
        action: string;
      }

      const body: ReviewBody = { user_id: GlobalState.userId(), action: action };
      await Api.post(`/sessions/${o.session_id}/outline/review`, body);
      this.toast(action === 'publish' ? '已发布并写入知识库' : '已退回');
      await this.load();
    } catch (e) {
      this.toast(`操作失败：${(e as Error).message}`);
    } finally {
      this.busy = false;
    }
  }

  build() {
    Row({ space: AppTheme.SPACE_L }) {
      // 左栏：待审列表
      Column({ space: AppTheme.SPACE_M }) {
        Text(`待审核提纲（${this.pendingList.length}）`)
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .width('100%')
        List({ space: AppTheme.SPACE_M }) {
          ForEach(this.pendingList, (o: Outline, index: number) => {
            ListItem() {
              AppCard({
                selected: this.selectedIndex === index,
                clickable: true,
                onCardClick: () => {
                  this.select(index);
                }
              }) {
                Column({ space: AppTheme.SPACE_XS }) {
                  Text(o.session_title ?? `课时 ${o.session_id}`)
                    .fontSize(AppTheme.FONT_BODY)
                    .fontColor(AppTheme.TEXT_PRIMARY)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`更新于 ${o.updated_at.substring(0, 16).replace('T', ' ')}`)
                    .fontSize(AppTheme.FONT_CAPTION)
                    .fontColor(AppTheme.TEXT_TERTIARY)
                }
                .alignItems(HorizontalAlign.Start)
              }
            }
          }, (o: Outline) => `${o.id}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width(280)
      .height('100%')

      // 右栏：编辑 + 操作
      Column({ space: AppTheme.SPACE_M }) {
        if (this.current() === null) {
          Column() {
            Text('暂无待审核提纲').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_TERTIARY)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Row({ space: AppTheme.SPACE_M }) {
            Text(`提纲编辑 · ${this.current()!.session_title ?? ''}`)
              .fontSize(AppTheme.FONT_SUBTITLE)
              .fontColor(AppTheme.TEXT_PRIMARY)
              .layoutWeight(1)
            if (this.dirty) {
              Text('未保存').fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.WARNING)
            }
          }
          .width('100%')

          TextArea({ text: this.editText })
            .width('100%')
            .layoutWeight(1)
            .fontSize(AppTheme.FONT_BODY)
            .backgroundColor(AppTheme.BG_CARD)
            .borderRadius(AppTheme.RADIUS_CARD)
            .onChange((v: string) => {
              this.editText = v;
              this.dirty = true;
            })

          Row({ space: AppTheme.SPACE_M }) {
            Button('保存修改')
              .layoutWeight(1)
              .enabled(!this.busy)
              .backgroundColor(AppTheme.BG_CARD)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .borderRadius(999)
              .onClick(() => {
                this.saveEdit();
              })
            Button('发布到共享池')
              .layoutWeight(1)
              .enabled(!this.busy)
              .backgroundColor(AppTheme.PRIMARY)
              .borderRadius(999)
              .onClick(() => {
                this.review('publish');
              })
            Button('退回')
              .layoutWeight(1)
              .enabled(!this.busy)
              .fontColor(AppTheme.DANGER)
              .backgroundColor(AppTheme.tagBg(AppTheme.DANGER))
              .borderRadius(999)
              .onClick(() => {
                this.review('reject');
              })
          }
          .width('100%')
        }
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .padding(AppTheme.SPACE_XL)
    .backgroundColor(AppTheme.BG_PAGE)
    .alignItems(VerticalAlign.Top)
  }
}
