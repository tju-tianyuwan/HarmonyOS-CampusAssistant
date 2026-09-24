import { TouchMotion } from '../common/TouchMotion';
import { LearningTheme as AppTheme } from '../common/LearningTheme';
import { CrystalIcon } from '../common/components/CrystalIcon';
import { MobileTabs } from '../common/components/MobileTabs';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

interface TeachingMaterial {
  id: number;
  kind: string;
  session_id: number;
  session_title: string;
  title: string;
  status: string;
  chars: number;
  updated_at: string;
}

@Component
export struct MaterialsPage {
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  onOpen: (sessionId: number, pane: string, resourceId: number) => void = () => {};
  @State items: TeachingMaterial[] = [];
  @State filter: string = 'all';
  @State search: string = '';
  @State loading: boolean = false;
  @State error: string = '';
  @State compact: boolean = true;
  private active: boolean = true;

  aboutToAppear(): void { this.active = true; this.load(); }
  aboutToDisappear(): void { this.active = false; }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      const data = JSON.parse(await Api.get(`/sessions/materials?class_course_id=${GlobalState.courseId()}`)) as TeachingMaterial[];
      if (this.active) { this.items = data; }
    } catch (e) { if (this.active) { this.error = (e as Error).message; } }
    finally { this.loading = false; }
  }

  private visibleItems(): TeachingMaterial[] {
    const query = this.search.trim().toLowerCase();
    return this.items.filter((item: TeachingMaterial) =>
      (this.filter === 'all' || this.filter === item.kind || (this.filter === 'pending' &&
        item.kind === 'outline' && ['draft', 'generated', 'pending'].includes(item.status))) &&
      (item.title + item.session_title).toLowerCase().includes(query));
  }

  private status(item: TeachingMaterial): string {
    if (item.kind === 'resource') { return '上传资料'; }
    if (item.status === 'published') { return '已发布'; }
    if (item.status === 'rejected') { return '已退回'; }
    return '待审核';
  }

  build() {
    Column({ space: 18 }) {
      Row() {
        Column({ space: 8 }) {
          Text('教学资料').fontSize(this.compact ? 24 : 30).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
          Text('按课次整理提纲与资料，审核后与学生共享').fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(19).fontColor([AppTheme.PRIMARY])
        }.stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width(44).height(44).borderRadius(16).backgroundColor(AppTheme.PRIMARY_LIGHT)
          .accessibilityText('刷新资料').enabled(!this.loading).onClick(() => { this.load(); })
      }.width('100%')
      Search({ value: this.search, placeholder: '搜索资料或课次' }).width('100%').height(48)
        .backgroundColor(AppTheme.BG_CARD).fontColor(AppTheme.INK)
        .onChange((value: string) => { this.search = value; })
      MobileTabs({ labels: ['全部', '提纲', '上传资料', '待审核'], keys: ['all', 'outline', 'resource', 'pending'],
        selected: this.filter, onSelect: (key: string) => { this.filter = key; } })
      if (this.loading) {
        LoadingProgress().width(32).height(32)
      } else if (this.error !== '') {
        Text(this.error).fontSize(14).fontColor(AppTheme.DANGER).width('100%')
        Button('重新加载').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).onClick(() => { this.load(); })
      } else if (this.visibleItems().length === 0) {
        Text(this.items.length === 0 ? '暂无教学资料' : '没有符合条件的资料')
          .fontSize(14).fontColor(AppTheme.TEXT_SECONDARY).width('100%').padding(16)
      }
      List({ space: 14 }) {
        ForEach(this.visibleItems(), (item: TeachingMaterial) => {
          ListItem() {
            Row({ space: 12 }) {
              CrystalIcon({ icon: item.kind === 'outline' ? $r('sys.symbol.doc_text') : $r('sys.symbol.folder'), edge: 40 })
              Column({ space: 8 }) {
                Text(item.title).fontSize(17).fontColor(AppTheme.INK).fontWeight(FontWeight.Medium).maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text(`${item.session_title} · ${item.chars} 字`).fontSize(12).fontColor(AppTheme.TEXT_SECONDARY)
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text(this.status(item)).fontSize(12).fontColor(item.status === 'published' ? AppTheme.SUCCESS : AppTheme.PRIMARY)
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 }).borderRadius(8)
                  .backgroundColor(AppTheme.PRIMARY_LIGHT)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([AppTheme.TEXT_SECONDARY])
            }.width('100%').padding(20).borderRadius(24).backgroundColor(AppTheme.BG_CARD)
              .border({ width: 1, color: '#F5FFFFFF' })
              .stateStyles({
                normal: { .translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
                pressed: { .translate(TouchMotion.pressedOffset(this.reduceMotion, 'card')).animation(TouchMotion.press(this.reduceMotion)) }
              })
              .onClick(() => { this.onOpen(item.session_id, item.kind === 'outline' ? 'outline' : 'resources',
                item.kind === 'resource' ? item.id : -1); })
          }
        }, (item: TeachingMaterial) => `${item.kind}_${item.id}`)
      }.width('100%').layoutWeight(1).lanes(this.compact ? 1 : 2, 16)
    }.width('100%').height('100%').padding(this.compact ? 16 : 28).backgroundColor(AppTheme.BG_PAGE)
      .onAreaChange((_oldArea: Area, newArea: Area) => { this.compact = Number(newArea.width) < 900; })
  }
}
