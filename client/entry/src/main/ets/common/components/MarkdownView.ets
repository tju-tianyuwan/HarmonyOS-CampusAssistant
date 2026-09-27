import { webview } from '@kit.ArkWeb';

class MarkdownSizeBridge {
  onResize: (height: number, width: number) => void = () => {};
  resize(height: number, width: number): void { this.onResize(height, width); }
}

/** Offline, sanitized Markdown + LaTeX. Source text is never inserted as executable HTML. */
@Component
export struct MarkdownView {
  @Prop @Watch('refreshContent') content: string = '';
  @Prop autoHeight: boolean = false;
  @Prop @Watch('refreshContent') textSize: number = 16;
  @Prop @Watch('refreshContent') textColor: string = '#193D55';
  @Prop bold: boolean = false;
  @State failed: boolean = false;
  @State measuredHeight: number = 32;
  private controller: webview.WebviewController = new webview.WebviewController();
  private sizeBridge: MarkdownSizeBridge = new MarkdownSizeBridge();
  private viewWidth: number = 0;
  private refreshTimer: number = -1;
  private ready: boolean = false;

  aboutToAppear(): void {
    this.sizeBridge.onResize = (height: number, width: number): void => {
      if (!this.ready || !this.autoHeight || !Number.isFinite(height) || !Number.isFinite(width) || width <= 0) { return; }
      const next = Math.max(28, Math.ceil(height * (this.viewWidth > 0 ? this.viewWidth / width : 1)) + 2);
      if (Math.abs(next - this.measuredHeight) > 1) { this.measuredHeight = next; }
    };
  }

  aboutToDisappear(): void {
    this.ready = false;
    if (this.refreshTimer !== -1) { clearTimeout(this.refreshTimer); this.refreshTimer = -1; }
    this.sizeBridge.onResize = () => {};
  }

  private refreshContent(): void {
    if (!this.ready || this.refreshTimer !== -1) { return; }
    // Coalesce streaming chunks without rebuilding the Web component or losing its position.
    this.refreshTimer = setTimeout(() => { this.refreshTimer = -1; this.renderContent(); }, 50);
  }

  private renderContent(): void {
    if (!this.ready) { return; }
    const encoded = JSON.stringify(this.content).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
    const color = JSON.stringify(this.textColor);
    try {
      this.controller.runJavaScript(`window.configureMarkdown(${this.autoHeight}, ${this.textSize}, ${color}, ${this.bold}); window.renderOutline(${encoded})`)
        .catch(() => { if (this.ready) { this.failed = true; } });
    } catch (e) { this.failed = true; }
  }

  build() {
    Column() {
      if (this.failed) {
        if (this.autoHeight) {
          Text(this.content).fontSize(this.textSize).fontColor(this.textColor).lineHeight(this.textSize * 1.75)
            .width('100%').copyOption(CopyOptions.InApp)
        } else {
        Scroll() {
          Text(this.content).fontSize(16).lineHeight(26).width('100%').copyOption(CopyOptions.InApp)
        }.width('100%').height('100%').padding(16)
        }
      } else {
        Web({ src: $rawfile('math/outline.html'), controller: this.controller })
          .width('100%').height(this.autoHeight ? this.measuredHeight : '100%').backgroundColor(Color.Transparent)
          .javaScriptAccess(true).domStorageAccess(false).fileAccess(false).onlineImageAccess(false)
          .javaScriptProxy({ object: this.sizeBridge, name: 'markdownSize', methodList: ['resize'], controller: this.controller })
          .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.PARENT_FIRST })
          .onPageEnd(() => { this.ready = true; this.refreshContent(); })
      }
    }.width('100%').height(this.autoHeight ? undefined : '100%').clip(true)
      .onAreaChange((oldArea: Area, area: Area) => {
        const width = Number(area.width);
        if (width > 0 && Math.abs(width - this.viewWidth) > 1) {
          this.viewWidth = width;
          this.refreshContent();
        }
      })
  }
}
