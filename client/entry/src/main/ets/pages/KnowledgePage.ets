import { picker, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

interface DocumentInfo { id: string; source: string; kind: string; chars: number; updated_at: string; }
interface KnowledgeStatus { mode: string; documents: DocumentInfo[]; needs_rebuild: boolean; }
interface Hit { text: string; source: string; warning?: string; }
interface SearchResult { hits: Hit[]; }
interface SearchRequest { question: string; }
interface DocumentRequest { source: string; content: string; }
interface ImportJob { id: string; filename: string; status: string; progress: number; error: string; }

@Component
export struct KnowledgePage {
  @State documents: DocumentInfo[] = [];
  @State hits: Hit[] = [];
  @State query: string = '';
  @State title: string = '';
  @State content: string = '';
  @State editing: boolean = false;
  @State busy: boolean = false;
  @State message: string = '';
  @State jobs: ImportJob[] = [];
  private timer: number = -1;
  private loading: boolean = false;
  private courseId: number = GlobalState.courseId();
  private active: boolean = true;
  aboutToAppear(): void { this.active = true; this.load(); this.timer = setInterval(() => { this.load(); }, 3000); }
  aboutToDisappear(): void { this.active = false; clearInterval(this.timer); }

  private async load(): Promise<void> {
    if (this.loading) { return; }
    this.loading = true;
    try {
      const status = JSON.parse(await Api.get(`/knowledge/${this.courseId}`)) as KnowledgeStatus;
      if (this.active) {
        this.documents = status.documents;
        if (status.needs_rebuild) { this.message = '向量索引待重建，当前使用关键词检索'; }
      }
      if (GlobalState.canManageCurrentCourse()) {
        const jobs = JSON.parse(await Api.get(`/knowledge/${this.courseId}/jobs`)) as ImportJob[];
        if (this.active) { this.jobs = jobs; }
      }
    } catch (e) { if (this.active) { this.message = (e as Error).message; } }
    finally { this.loading = false; }
  }

  private async action(kind: string, id: string = ''): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.message = '';
    try {
      if (kind === 'search') {
        const body: SearchRequest = { question: this.query };
        const result = JSON.parse(await Api.post(`/knowledge/${this.courseId}/search`, body)) as SearchResult;
        if (this.active) { this.hits = result.hits; this.message = result.hits.length === 0 ? '没有找到相关资料' : ''; }
      } else if (kind === 'save') {
        const body: DocumentRequest = { source: this.title, content: this.content };
        await Api.postLong(`/knowledge/${this.courseId}/documents`, body);
        this.editing = false;
        this.content = '';
        this.title = '';
      } else if (kind === 'remove') {
        await Api.remove(`/knowledge/${this.courseId}/documents/${encodeURIComponent(id)}`);
      } else if (kind === 'retry') {
        await Api.post(`/knowledge/${this.courseId}/jobs/${id}/retry`);
      } else if (kind === 'upload') {
        const files = await new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext).select({ maxSelectNumber: 1 });
        if (files.length === 0) { return; }
        const file = await fileIo.open(files[0], fileIo.OpenMode.READ_ONLY);
        try {
          const info = await fileIo.stat(file.fd);
          if (info.size > 50 * 1024 * 1024) { throw new Error('文件不能超过 50 MiB'); }
          const data = new ArrayBuffer(info.size);
          const read = await fileIo.read(file.fd, data);
          if (read !== info.size) { throw new Error('文件读取不完整'); }
          const filename = decodeURIComponent(files[0].substring(files[0].lastIndexOf('/') + 1));
          await Api.upload(`/knowledge/${this.courseId}/imports`, filename, data);
          this.message = '资料已上传，正在后台处理';
        } finally { await fileIo.close(file); }
      } else {
        await Api.postLong(`/knowledge/${this.courseId}/${kind}`, {} as Record<string, string>);
        this.message = kind === 'embedding-test' ? 'Embedding 连接成功' : '知识库已重建';
      }
      await this.load();
    } catch (e) { if (this.active) { this.message = (e as Error).message; } }
    finally { this.busy = false; }
  }

  build() {
    Column({ space: 12 }) {
      Text('课程知识库').fontSize(22).fontWeight(FontWeight.Bold).width('100%')
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        if (GlobalState.canManageCurrentCourse()) {
          Button('上传资料').onClick(() => { this.action('upload'); })
          Button('新建文本').onClick(() => { this.editing = !this.editing; })
          Button('重建索引').onClick(() => { this.action('rebuild'); })
          Button('连接测试').onClick(() => { this.action('embedding-test'); })
        }
      }.width('100%').enabled(!this.busy)
      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索课程资料', text: this.query }).layoutWeight(1).onChange((v: string) => { this.query = v; })
        Button('搜索').enabled(!this.busy && this.query.trim() !== '').onClick(() => { this.action('search'); })
      }
      if (this.message !== '') { Text(this.message).fontSize(13).fontColor(AppTheme.TEXT_SECONDARY).width('100%') }
      if (this.busy) { LoadingProgress().width(28).height(28) }
      if (this.editing) {
        TextInput({ placeholder: '资料标题', text: this.title }).onChange((v: string) => { this.title = v; })
        TextArea({ placeholder: '资料正文', text: this.content }).height(150).onChange((v: string) => { this.content = v; })
        Button('保存资料').enabled(!this.busy).onClick(() => { this.action('save'); })
      }
      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.jobs, (job: ImportJob) => {
            if (job.status !== 'done') {
              Column({ space: 6 }) {
                Text(job.filename).fontSize(15).width('100%')
                Text(job.status === 'failed' ? job.error : job.status === 'queued' ? '等待处理' : `正在处理 ${job.progress}%`)
                  .fontSize(13).fontColor(job.status === 'failed' ? AppTheme.DANGER : AppTheme.TEXT_SECONDARY).width('100%')
                if (job.status === 'processing') { Progress({ value: job.progress, total: 100 }).width('100%') }
                if (job.status === 'failed') { Button('重试').enabled(!this.busy).onClick(() => { this.action('retry', job.id); }) }
              }.width('100%').padding(12).backgroundColor(AppTheme.PRIMARY_LIGHT).borderRadius(8)
            }
          }, (job: ImportJob) => `${job.id}_${job.status}_${job.progress}`)
          ForEach(this.hits, (hit: Hit) => {
            Column({ space: 6 }) {
              Text(hit.source).fontWeight(FontWeight.Bold).width('100%')
              Text(hit.text).fontSize(14).width('100%')
              if (hit.warning) { Text(hit.warning).fontSize(12).fontColor(AppTheme.WARNING) }
            }.width('100%').padding(14).backgroundColor(AppTheme.PRIMARY_LIGHT).borderRadius(8)
          })
          ForEach(this.documents, (doc: DocumentInfo) => {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text(doc.source).fontSize(16).width('100%')
                Text(`${doc.chars} 字 · ${doc.kind}`).fontSize(12).fontColor(AppTheme.TEXT_TERTIARY).width('100%')
              }.layoutWeight(1)
              if (doc.kind === 'manual' && GlobalState.canManageCurrentCourse()) {
                Button('删除').enabled(!this.busy).fontColor(AppTheme.DANGER).backgroundColor(Color.Transparent)
                  .onClick(() => { this.action('remove', doc.id); })
              }
            }.width('100%').padding(14).backgroundColor('#FFFFFF').borderRadius(8)
          }, (doc: DocumentInfo) => doc.id)
        }.width('100%')
      }.layoutWeight(1).width('100%')
    }.padding(24).width('100%').height('100%').backgroundColor(AppTheme.BG_PAGE)
  }
}
