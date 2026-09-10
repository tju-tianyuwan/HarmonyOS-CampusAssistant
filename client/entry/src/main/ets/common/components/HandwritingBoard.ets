import { AppTheme } from '../AppTheme';
import { HandwritingDoc, Stroke, StrokePoint } from '../../model/Models';

interface PenColor {
  key: string;
  value: string;
}

const PEN_COLORS: PenColor[] = [
  { key: 'ink', value: '#111111' },
  { key: 'teal', value: '#21D5CE' },
  { key: 'blue', value: '#5B8DEF' },
  { key: 'red', value: '#F5554A' },
  { key: 'orange', value: '#FF9F43' }
];

const PEN_WIDTHS: number[] = [2, 4, 7];

/**
 * 手写画板（Notein 风）：全幅画布 + 底部居中悬浮笔盒
 * （笔/橡皮 · 色板 · 笔宽圆点 · 撤销/清空）。
 * 矢量笔迹存储，触控笔压力映射粗细，手指和鼠标使用固定宽度。
 */
@Component
export struct HandwritingBoard {
  /** 初始笔迹 JSON（HandwritingDoc），空串为新画板 */
  initialJson: string = '';
  /** 只读预览模式：不响应书写，也不展示笔盒 */
  readOnly: boolean = false;
  /** 笔迹变化回调（抬笔时触发，返回完整 JSON） */
  onStrokesChanged: (json: string) => void = (json: string) => {
  };
  @State tool: string = 'pen'; // pen | eraser
  @State penColor: string = '#111111';
  @State penWidth: number = 4;
  @State strokeCount: number = 0;
  private strokes: Stroke[] = [];
  private currentStroke: Stroke | null = null;
  private pointerId: number = -1;
  private pointerIsPen: boolean = false;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private readonly eraserWidth: number = 26;
  private documentWidth: number = 0;
  private documentHeight: number = 0;
  private drawingScale: number = 1;

  aboutToAppear(): void {
    if (this.initialJson.trim() !== '') {
      try {
        const doc: HandwritingDoc = JSON.parse(this.initialJson) as HandwritingDoc;
        this.strokes = doc.strokes;
        this.documentWidth = Number.isFinite(doc.width) ? doc.width! : 0;
        this.documentHeight = Number.isFinite(doc.height) ? doc.height! : 0;
        this.strokeCount = this.strokes.length;
      } catch (e) {
        this.strokes = [];
      }
    }
  }

  private getPressure(event: TouchEvent): number {
    if (event.sourceTool !== SourceTool.Pen || !Number.isFinite(event.pressure)) { return 1; }
    return Math.max(0.05, Math.min(1, event.pressure));
  }

  private emit(): void {
    const doc: HandwritingDoc = { strokes: this.strokes, width: this.documentWidth, height: this.documentHeight };
    this.onStrokesChanged(JSON.stringify(doc));
  }

  private drawSegment(from: StrokePoint, to: StrokePoint, stroke: Stroke): void {
    this.ctx.beginPath();
    this.ctx.lineCap = 'round';
    this.ctx.lineJoin = 'round';
    this.ctx.strokeStyle = stroke.eraser ? '#FFFFFF' : stroke.color;
    this.ctx.lineWidth = stroke.width * (stroke.eraser ? 1 : Math.max(0.05, (from.p + to.p) / 2));
    this.ctx.moveTo(from.x, from.y);
    this.ctx.lineTo(to.x, to.y);
    this.ctx.stroke();
  }

  private drawDot(point: StrokePoint, stroke: Stroke): void {
    this.ctx.beginPath();
    this.ctx.fillStyle = stroke.eraser ? '#FFFFFF' : stroke.color;
    this.ctx.arc(point.x, point.y, stroke.width * (stroke.eraser ? 1 : Math.max(0.05, point.p)) / 2, 0, Math.PI * 2);
    this.ctx.fill();
  }

  private redraw(): void {
    if (this.ctx.width <= 0 || this.ctx.height <= 0) { return; }
    if (this.documentWidth <= 0 || this.documentHeight <= 0) {
      let maxX: number = 0;
      let maxY: number = 0;
      for (const stroke of this.strokes) {
        for (const point of stroke.points) { maxX = Math.max(maxX, point.x + stroke.width); maxY = Math.max(maxY, point.y + stroke.width); }
      }
      this.documentWidth = Math.max(this.ctx.width, maxX + 16);
      this.documentHeight = Math.max(this.ctx.height - 80, maxY + 16);
    }
    this.drawingScale = Math.min(this.ctx.width / this.documentWidth, Math.max(1, this.ctx.height - 80) / this.documentHeight);
    this.ctx.resetTransform();
    this.ctx.clearRect(0, 0, this.ctx.width, this.ctx.height);
    this.ctx.fillStyle = '#F2F5F4';
    this.ctx.fillRect(0, 0, this.ctx.width, this.ctx.height);
    this.ctx.scale(this.drawingScale, this.drawingScale);
    this.ctx.fillStyle = '#FFFFFF';
    this.ctx.fillRect(0, 0, this.documentWidth, this.documentHeight);
    for (const s of this.strokes) {
      if (s.points.length === 1) { this.drawDot(s.points[0], s); }
      for (let i = 1; i < s.points.length; i++) {
        this.drawSegment(s.points[i - 1], s.points[i], s);
      }
    }
  }

  private handleTouch(event: TouchEvent): void {
    const isPen = event.sourceTool === SourceTool.Pen;
    if (this.currentStroke !== null && this.pointerIsPen && !isPen) { return; }
    if (event.type === TouchType.Cancel) {
      this.currentStroke = null; this.pointerId = -1; this.redraw(); return;
    }
    if (event.type === TouchType.Down) {
      if (this.currentStroke !== null) {
        if (!isPen || this.pointerIsPen) { return; }
        this.currentStroke = null; this.redraw();
      }
      const t = event.changedTouches[0];
      if (t === undefined) { return; }
      this.pointerId = t.id;
      this.pointerIsPen = isPen;
      const p: StrokePoint = { x: t.x / this.drawingScale, y: t.y / this.drawingScale, p: this.getPressure(event) };
      if (p.x > this.documentWidth || p.y > this.documentHeight) { return; }
      const isEraser: boolean = this.tool === 'eraser';
      this.currentStroke = {
        points: [p],
        width: (isEraser ? this.eraserWidth : this.penWidth) / this.drawingScale,
        color: this.penColor,
        eraser: isEraser
      };
      this.drawDot(p, this.currentStroke);
    } else if (event.type === TouchType.Move && this.currentStroke !== null) {
      const t = event.changedTouches.find((touch: TouchObject) => touch.id === this.pointerId);
      if (t === undefined) { return; }
      const p: StrokePoint = { x: Math.min(this.documentWidth, Math.max(0, t.x / this.drawingScale)),
        y: Math.min(this.documentHeight, Math.max(0, t.y / this.drawingScale)), p: this.getPressure(event) };
      const pts: StrokePoint[] = this.currentStroke.points;
      pts.push(p);
      if (pts.length >= 2) {
        this.drawSegment(pts[pts.length - 2], pts[pts.length - 1], this.currentStroke);
      }
    } else if (event.type === TouchType.Up && this.currentStroke !== null) {
      if (!event.changedTouches.some((touch: TouchObject) => touch.id === this.pointerId)) { return; }
      if (this.currentStroke.points.length > 0) {
        this.strokes.push(this.currentStroke);
        this.strokeCount = this.strokes.length;
        this.emit();
      }
      this.currentStroke = null;
      this.pointerId = -1;
    }
  }

  @Builder
  penBoxDivider() {
    Column()
      .width(1)
      .height(24)
      .backgroundColor(AppTheme.DIVIDER)
      .margin({ left: 6, right: 6 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .borderRadius(AppTheme.RADIUS_CARD)
        .backgroundColor('#FFFFFF')
        .shadow({ radius: 16, color: 'rgba(17,17,17,0.04)', offsetX: 0, offsetY: 4 })
        .onReady(() => {
          this.redraw();
        })
        .onAreaChange(() => { this.currentStroke = null; this.pointerId = -1; this.redraw(); })
        .onTouch((event: TouchEvent) => {
          if (!this.readOnly) {
            this.handleTouch(event);
          }
        })

      // 悬浮笔盒
      if (!this.readOnly) {
        Scroll() {
        Row({ space: AppTheme.SPACE_S }) {
          Text('✒️')
            .fontSize(18)
            .width(36)
            .height(36)
            .textAlign(TextAlign.Center)
            .borderRadius(18)
            .backgroundColor(this.tool === 'pen' ? AppTheme.PRIMARY_LIGHT : 'transparent')
            .onClick(() => {
              this.tool = 'pen';
            })
          Text('🧽')
            .fontSize(18)
            .width(36)
            .height(36)
            .textAlign(TextAlign.Center)
            .borderRadius(18)
            .backgroundColor(this.tool === 'eraser' ? AppTheme.PRIMARY_LIGHT : 'transparent')
            .onClick(() => {
              this.tool = 'eraser';
            })

          this.penBoxDivider()

          ForEach(PEN_COLORS, (c: PenColor) => {
            Column()
              .width(this.penColor === c.value ? 22 : 18)
              .height(this.penColor === c.value ? 22 : 18)
              .borderRadius(11)
              .backgroundColor(c.value)
              .border({
                width: this.penColor === c.value ? 2 : 0,
                color: AppTheme.PRIMARY_LIGHT
              })
              .onClick(() => {
                this.penColor = c.value;
                this.tool = 'pen';
              })
          }, (c: PenColor) => c.key)

          this.penBoxDivider()

          ForEach(PEN_WIDTHS, (w: number) => {
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width(26)
                .height(26)
                .borderRadius(13)
                .border({
                  width: this.penWidth === w ? 1.5 : 0,
                  color: AppTheme.PRIMARY
                })
              Column()
                .width(w + 3)
                .height(w + 3)
                .borderRadius((w + 3) / 2)
                .backgroundColor(AppTheme.INK)
            }
            .onClick(() => {
              this.penWidth = w;
              this.tool = 'pen';
            })
          }, (w: number) => `${w}`)

          this.penBoxDivider()

          Text('↩')
            .fontSize(18)
            .fontColor(AppTheme.TEXT_SECONDARY)
            .width(36)
            .height(36)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              if (this.strokes.length > 0) {
                this.strokes.pop();
                this.strokeCount = this.strokes.length;
                this.redraw();
                this.emit();
              }
            })
          Text('🗑')
            .fontSize(16)
            .width(36)
            .height(36)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.strokes = [];
              this.strokeCount = 0;
              this.redraw();
              this.emit();
            })
        }
        .padding({ left: AppTheme.SPACE_L, right: AppTheme.SPACE_L, top: AppTheme.SPACE_S, bottom: AppTheme.SPACE_S })
        .borderRadius(999)
        .backgroundColor(AppTheme.BG_CARD)
        .shadow({ radius: 26, color: 'rgba(17,17,17,0.12)', offsetX: 0, offsetY: 5 })
        .alignItems(VerticalAlign.Center)
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          .constraintSize({ maxWidth: '96%' }).height(68).margin({ bottom: AppTheme.SPACE_L })
      }
    }
    .width('100%')
    .height('100%')
  }
}
