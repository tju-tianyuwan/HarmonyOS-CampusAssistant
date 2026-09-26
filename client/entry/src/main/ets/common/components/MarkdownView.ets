import { webview } from '@kit.ArkWeb';

/** Offline, sanitized Markdown + LaTeX. Source text is never inserted as executable HTML. */
@Component
export struct MarkdownView {
  @Prop @Watch('refreshContent') content: string = '';
  @State failed: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private ready: boolean = false;

  aboutToDisappear(): void { this.ready = false; }

  private refreshContent(): void {
    if (!this.ready) { return; }
    const encoded = JSON.stringify(this.content).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
    try {
      this.controller.runJavaScript(`window.renderOutline(${encoded})`).catch(() => { this.failed = true; });
    } catch (e) { this.failed = true; }
  }

  build() {
    Column() {
      if (this.failed) {
        Scroll() {
          Text(this.content).fontSize(16).lineHeight(26).width('100%').copyOption(CopyOptions.InApp)
        }.width('100%').height('100%').padding(16)
      } else {
        Web({ src: $rawfile('math/outline.html'), controller: this.controller })
          .width('100%').height('100%').backgroundColor(Color.Transparent)
          .javaScriptAccess(true).domStorageAccess(false).fileAccess(false).onlineImageAccess(false)
          .onPageEnd(() => { this.ready = true; this.refreshContent(); })
      }
    }.width('100%').height('100%').clip(true)
  }
}
