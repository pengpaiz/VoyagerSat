import { SatelliteListPage } from '../view/pages/SatelliteListPage';
import { PassesPage } from '../view/pages/PassesPage';
import { MapPage } from '../view/pages/MapPage';
import { CalendarPage } from '../view/pages/CalendarPage';
import { SettingsPage } from '../view/pages/SettingsPage';
import { SatelliteApp } from '../common/SatelliteApp';
import { SelectedSats } from '../common/SelectedSats';
import { Favorites } from '../common/Favorites';
import { AppSettings } from '../common/AppSettings';
import { CalendarForecast } from '../domain/predict/CalendarForecast';
import { KEY_BAR_CLEARANCE } from '../common/LayoutMetrics';
import { curves, uiMaterial, window } from '@kit.ArkUI';

/** 默认停留标签（2 = 过境） */
const DEFAULT_TAB = 2;
/** 中间突出显示的页签（过境） */
const CENTER_INDEX = 2;
/** 中间「过境」按钮的强调色 */
const CENTER_ACCENT = '#FFD54F';
/** 任务栏胶囊底：毛玻璃 + 一层很淡的白，避免深色主题下显得是黑底 */
const BAR_CAPSULE_TINT = '#1FFFFFFF';
/** 悬浮栏几何兜底值（vp）；真实值由容器实测高度推算，见 barHeightVp()/barBottomVp() */
const BAR_HEIGHT_BASE = 70;
const BAR_BOTTOM_BASE = 6;
/** 悬浮栏左右边距（vp） */
const BAR_SIDE_MARGIN = 16;
/** 图标行相对胶囊底的内缩：保证最左/最右页签的高亮胶囊完整落在胶囊底内（不被圆角切掉） */
const BAR_CELL_INSET = 18;
/** 高亮胶囊宽度 = 格宽 × 该比例；胶囊高度 = 栏高 - 该值 */
const PILL_WIDTH_RATIO = 0.78;
const PILL_HEIGHT_INSET = 6;
/** 静止时胶囊的"略大"尺寸 */
const REST_SCALE = 1.12;
/** 页面入场：起始不透明度与上浮距离 */
const PAGE_FX_MIN_OPACITY = 0.4;
const PAGE_FX_OFFSET = 14;

/** 底栏页签数据模型 */
class GlassTabItem {
  title: string;
  icon: Resource;

  constructor(title: string, icon: Resource) {
    this.title = title;
    this.icon = icon;
  }
}

/**
 * 底部悬浮玻璃任务栏（跟手混合版）
 *
 * 结构：Tabs（barHeight=0，只负责承载 5 个页面）+ 自绘悬浮栏（玻璃背板 + 高亮胶囊 + Symbol 图标）
 *
 * 为什么不让系统画栏：系统悬浮栏在部分设备上会自带避让/断点宽度，
 * 实测会出现"栏下多出一截空白"。改为 barHeight(0) 后页面内容铺满整屏，
 * 栏的位置只由本组件的 padding 决定，几何完全确定、与机型无关。
 *
 * 动画语言（任务栏与页面统一）：
 * - 胶囊跟手拖动，按累计距离放大、按速度变扁、按纵向偏移形变，松手吸附并 Q 弹回
 * - 图标按与胶囊的距离 smoothstep 缩放/抬起/变色
 * - 页面切换入场：同一套 springMotion(0.32, 0.62) 驱动淡入 + 上浮
 */
@Entry
@Component
struct Index {
  // ---- 状态 ----
  @State selectedIndex: number = DEFAULT_TAB;
  @State indicatorX: number = 0;
  @State innerWidth: number = 0;
  @State isDragging: boolean = false;
  @State rootH: number = 0;
  /** 底部导航条（手势条）避让高度：内容铺到屏底后，胶囊栏要落在它上方 */
  @State navInset: number = 0;
  /** 顶部状态栏避让高度：窗口铺满整屏后由页面自己让出 */
  @State statusInset: number = 0;
  private barClearance: number = 0;
  @State pillScaleX: number = REST_SCALE;
  @State pillScaleY: number = REST_SCALE;
  /** 页面入场进度 0→1（淡入 + 上浮） */
  @State pageFx: number = 1;
  /** 日历 14 天预报的预热输入：任一变化就后台预计算，保证切到日历页即可用 */
  @StorageProp('selected_version') @Watch('onForecastInputsChanged') selectedVersion: number = 0;
  @StorageProp('data_version') @Watch('onForecastInputsChanged') dataVersion: number = 0;
  @StorageProp('station_version') @Watch('onForecastInputsChanged') stationVersion: number = 0;

  // ---- 拖动临时量 ----
  private dragStartX: number = 0;
  private maxDragDist: number = 0;
  private lastMoveX: number = 0;
  private lastMoveTime: number = 0;
  private flingVelocity: number = 0;

  private tabsController: TabsController = new TabsController();
  private app: SatelliteApp = SatelliteApp.getInstance();
  private items: GlassTabItem[] = [
    new GlassTabItem('卫星', $r('sys.symbol.satellite')),
    new GlassTabItem('地图', $r('sys.symbol.map')),
    new GlassTabItem('过境', $r('sys.symbol.dot_radiowaves_left_and_right')),
    new GlassTabItem('日历', $r('sys.symbol.calendar')),
    new GlassTabItem('设置', $r('sys.symbol.gearshape'))
  ];

  aboutToAppear(): void {
    // 首个可见标签：各地图/过境/日历页据此判断是否值得立刻重算
    AppStorage.setOrCreate<number>('current_tab', this.selectedIndex);
    this.app.init(getContext(this));
    SelectedSats.init();
    Favorites.init();
    AppSettings.init();
    // 读取状态栏/底部导航条避让高度：窗口已铺满整屏，安全区由页面自己让出
    window.getLastWindow(getContext(this)).then((win: window.Window): void => {
      const status = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const nav = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.statusInset = this.getUIContext().px2vp(status.topRect.height);
      this.navInset = this.getUIContext().px2vp(nav.bottomRect.height);
      this.publishBarClearance();
    });
    // 先加载本地数据，再静默联网更新，避免竞态导致首页空白
    this.app.loadFromDisk().then((): void => {
      // 本地数据就绪后立刻预热日历预报（后台逐颗算，不阻塞交互）
      this.warmCalendarForecast();
      this.app.silentStartupUpdate();
    });
    // 读取内置镜像（打包快照）的版本时间，供设置页标明
    this.app.loadSnapshotInfo();
  }

  /** 选择集 / 数据 / 站址变化时后台补算日历预报，使日历与过境页随时一致。 */
  onForecastInputsChanged(): void {
    this.warmCalendarForecast();
  }

  private warmCalendarForecast(): void {
    CalendarForecast.getInstance().warmup(SelectedSats.getCats(), this.dataVersion);
  }

  // ---- 几何 ----

  /** 悬浮栏高度：按容器实测高度自适应（64~76vp，比上一版更高＝向下扩展） */
  private barHeightVp(): number {
    if (this.rootH <= 0) {
      return BAR_HEIGHT_BASE;
    }
    const scaled = Math.round(this.rootH * 0.085);
    return Math.max(64, Math.min(76, scaled));
  }

  /** 悬浮栏距底距离（4~10vp）+ 导航条避让：让栏尽量靠下 */
  private barBottomVp(): number {
    if (this.rootH <= 0) {
      return BAR_BOTTOM_BASE;
    }
    const scaled = Math.round(this.rootH * 0.010);
    return Math.max(4, Math.min(10, scaled));
  }

  /** 悬浮栏到屏幕底的真实间距（含导航条避让区） */
  private barBottomEdgeVp(): number {
    return this.barBottomVp() + this.navInset;
  }

  /**
   * 页面滚动内容需要预留的底部空间（内容铺到屏底，靠这段把最后一条滚到胶囊上方）。
   * 发布到 AppStorage，供各页统一使用，保证五个页面底部一致。
   */
  private publishBarClearance(): void {
    const clearance = Math.ceil(this.barBottomEdgeVp() + this.barHeightVp() + 6);
    if (clearance !== this.barClearance) {
      this.barClearance = clearance;
      AppStorage.setOrCreate<number>(KEY_BAR_CLEARANCE, clearance);
    }
  }

  /** 胶囊高度与顶部内距（垂直居中于栏内） */
  private pillHeightVp(): number {
    return this.barHeightVp() - PILL_HEIGHT_INSET;
  }

  private pillTopVp(): number {
    return PILL_HEIGHT_INSET / 2;
  }

  /** 单个页签格宽度 */
  private cellWidth(): number {
    return this.innerWidth / this.items.length;
  }

  /** 第 index 格中心 X */
  private cellCenter(index: number): number {
    return this.cellWidth() * index + this.cellWidth() / 2;
  }

  /** 胶囊当前覆盖的页签索引 */
  private activeIndex(): number {
    if (this.cellWidth() <= 0) {
      return this.selectedIndex;
    }
    const raw = Math.round((this.indicatorX - this.cellWidth() / 2) / this.cellWidth());
    return Math.max(0, Math.min(this.items.length - 1, raw));
  }

  /** smoothstep：边缘过渡更柔和 */
  private smooth(t: number): number {
    const x = Math.max(0, Math.min(1, t));
    return x * x * (3 - 2 * x);
  }

  /** 图标形变强度 0~1（影响半径 = 0.9 格宽） */
  private deformRatio(index: number): number {
    const radius = this.cellWidth() * 0.9;
    if (radius <= 0) {
      return 0;
    }
    const dist = Math.abs(this.indicatorX - this.cellCenter(index));
    return this.smooth(1 - dist / radius);
  }

  /** 选中态用主题主色，未选中用次要文字色（深浅色主题自适应） */
  private iconColor(index: number): ResourceColor {
    return this.activeIndex() === index
      ? $r('app.color.color_primary')
      : $r('app.color.color_text_secondary');
  }

  /** 中间（过境）按钮：固定强调色 #FFD54F */
  private itemIconColor(index: number): ResourceColor {
    if (index === CENTER_INDEX) {
      return CENTER_ACCENT;
    }
    return this.iconColor(index);
  }

  /** 中间按钮文字同用强调色 */
  private itemLabelColor(index: number): ResourceColor {
    if (index === CENTER_INDEX) {
      return CENTER_ACCENT;
    }
    return this.iconColor(index);
  }

  // ---- 动画 ----

  /** 移动胶囊到目标 X */
  private moveIndicator(x: number, curve: ICurve): void {
    this.getUIContext().animateTo({ curve: curve }, (): void => {
      this.indicatorX = x;
    });
  }

  /** 统一入口设置胶囊缩放（避免多个 animateTo 竞争同一属性） */
  private setPillScale(x: number, y: number, curve: ICurve, duration?: number): void {
    this.getUIContext().animateTo({ curve: curve, duration: duration }, (): void => {
      this.pillScaleX = x;
      this.pillScaleY = y;
    });
  }

  /** 拖动中的三维形变：累计距离放大 + 速度变扁 + 纵向偏移形变 */
  private updatePillStretch(totalDistance: number, velocity: number, verticalOffset: number): void {
    const grow = Math.min(0.85, Math.abs(totalDistance) / 55);
    const s = Math.max(REST_SCALE, 1 + grow);
    const velRatio = Math.min(1, Math.abs(velocity) / 1.5);
    const flatness = 0.2 * velRatio;
    const yDeform = Math.max(-0.15, Math.min(0.15, -verticalOffset / 200));
    this.setPillScale(s * (1 + flatness), s * (1 - flatness + yDeform), curves.springMotion(0.28, 0.62));
  }

  /** 松手回弹：快速甩动先挤压再 Q 弹回静止尺寸 */
  private resetPillStretch(): void {
    if (Math.abs(this.flingVelocity) > 0.6) {
      const squeezeX = 1 - Math.min(0.35, Math.abs(this.flingVelocity) * 0.3);
      const squeezeY = 1 + Math.min(0.25, Math.abs(this.flingVelocity) * 0.2);
      this.setPillScale(squeezeX, squeezeY, curves.springMotion(0.25, 0.5), 90);
    }
    this.setPillScale(REST_SCALE, REST_SCALE, curves.springMotion(1.0, 0.7));
  }

  /**
   * 页面入场动画：与任务栏胶囊同一套弹簧曲线。
   * 先把进度瞬回 0（duration=0，不产生动画），下一帧再动画到 1，
   * 避免同一帧内"归零 + 动画到 1"被框架吞掉而看不到动画。
   */
  private playEnterFx(): void {
    this.getUIContext().animateTo({ duration: 0, curve: Curve.Linear }, (): void => {
      this.pageFx = 0;
    });
    setTimeout((): void => {
      this.getUIContext().animateTo({ curve: curves.springMotion(0.32, 0.62) }, (): void => {
        this.pageFx = 1;
      });
    }, 0);
  }

  /** 点击切换：复用拖动视觉序列 */
  private selectTab(index: number): void {
    const targetX = this.cellCenter(index);
    const distance = Math.abs(targetX - this.indicatorX);
    this.updatePillStretch(distance, 0, 0);
    this.selectedIndex = index;
    AppStorage.setOrCreate<number>('current_tab', index);
    this.tabsController.changeIndex(index);
    this.moveIndicator(targetX, curves.springMotion(0.55, 0.82));
    // 根据距离估算弹簧到达时间，到了再缩小，避免还没到就变小
    const arriveMs = Math.max(60, Math.min(200, distance * 0.8));
    setTimeout((): void => {
      this.resetPillStretch();
    }, arriveMs);
  }

  /** 系统 tabBar 置空（栏高为 0，仅占位以保证 TabContent 合法） */
  @Builder
  emptyTabBar() {
    Column().width('100%').height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // === 内容层：barHeight(0) → 页面铺满整屏，栏的位置完全由下方浮栏决定 ===
      Tabs({ barPosition: BarPosition.End, index: this.selectedIndex, controller: this.tabsController }) {
        TabContent() {
          Column() {
            SatelliteListPage()
          }
          .width('100%')
          .height('100%')
          .opacity(PAGE_FX_MIN_OPACITY + (1 - PAGE_FX_MIN_OPACITY) * this.pageFx)
          .translate({ y: PAGE_FX_OFFSET * (1 - this.pageFx) })
        }
        .tabBar(this.emptyTabBar())

        TabContent() {
          Column() {
            MapPage()
          }
          .width('100%')
          .height('100%')
          .opacity(PAGE_FX_MIN_OPACITY + (1 - PAGE_FX_MIN_OPACITY) * this.pageFx)
          .translate({ y: PAGE_FX_OFFSET * (1 - this.pageFx) })
        }
        .tabBar(this.emptyTabBar())

        TabContent() {
          Column() {
            PassesPage()
          }
          .width('100%')
          .height('100%')
          .opacity(PAGE_FX_MIN_OPACITY + (1 - PAGE_FX_MIN_OPACITY) * this.pageFx)
          .translate({ y: PAGE_FX_OFFSET * (1 - this.pageFx) })
        }
        .tabBar(this.emptyTabBar())

        TabContent() {
          Column() {
            CalendarPage()
          }
          .width('100%')
          .height('100%')
          .opacity(PAGE_FX_MIN_OPACITY + (1 - PAGE_FX_MIN_OPACITY) * this.pageFx)
          .translate({ y: PAGE_FX_OFFSET * (1 - this.pageFx) })
        }
        .tabBar(this.emptyTabBar())

        TabContent() {
          Column() {
            SettingsPage()
          }
          .width('100%')
          .height('100%')
          .opacity(PAGE_FX_MIN_OPACITY + (1 - PAGE_FX_MIN_OPACITY) * this.pageFx)
          .translate({ y: PAGE_FX_OFFSET * (1 - this.pageFx) })
        }
        .tabBar(this.emptyTabBar())
      }
      .barMode(BarMode.Fixed)
      .vertical(false)
      .barHeight(0)
      .backgroundColor($r('app.color.color_bg'))
      // 窗口铺满整屏后，顶部状态栏的避让由这里让出（页面内容不会被状态栏压住）
      .padding({ top: this.statusInset })
      .onChange((index: number): void => {
        this.selectedIndex = index;
        AppStorage.setOrCreate<number>('current_tab', index);
        if (!this.isDragging && this.innerWidth > 0) {
          this.moveIndicator(this.cellCenter(index), curves.springMotion(0.32, 0.6));
        }
        // 内容入场：点击 / 拖动松手 / 横滑切换都会经过这里
        this.playEnterFx();
      })
      .width('100%')
      .height('100%')

      // === 浮栏：胶囊形毛玻璃底 + 高亮胶囊 + 图标（全部浮在内容之上）===
      Column() {
        Stack() {
          // 胶囊形底：整条栏做成胶囊（两端全圆）的鸿蒙毛玻璃
          Column()
            .width('100%')
            .height('100%')
            .borderRadius(999)
            .backgroundColor(BAR_CAPSULE_TINT)
            .backgroundBlurStyle(BlurStyle.Thin)
            .systemMaterial(new uiMaterial.ImmersiveMaterial({
              style: uiMaterial.ImmersiveStyle.THIN,
              applyShadow: true,
              interactive: true
            }))
            .shadow({ radius: 14, color: '#26000000', offsetY: 4 })

          // 高亮胶囊：跟随手势滑动，标识当前页签
          // x 需加上 BAR_CELL_INSET：图标行整体内缩，胶囊要落在同一坐标系里，
          // 否则在最左/最右页签时胶囊会顶到胶囊底的圆角外，看起来"没填满"
          Column()
            .width(this.cellWidth() * PILL_WIDTH_RATIO)
            .height(this.pillHeightVp())
            .borderRadius(999)
            .backgroundColor($r('app.color.color_card'))
            .opacity(0.95)
            .scale({ x: this.pillScaleX, y: this.pillScaleY })
            .position({
              x: BAR_CELL_INSET + this.indicatorX - (this.cellWidth() * PILL_WIDTH_RATIO) / 2,
              y: this.pillTopVp()
            })

          // 图标 + 文字（左右各内缩 BAR_CELL_INSET，让最外侧的高亮完整落在胶囊底内）
          Row() {
            Row() {
              ForEach(this.items, (item: GlassTabItem, index: number) => {
                Column() {
                  Stack() {
                    // 中间（过境）底圈：未选中时淡强调色光晕；选中时由滑动胶囊负责高亮
                    if (index === CENTER_INDEX) {
                      Column()
                        .width(40)
                        .height(40)
                        .borderRadius(20)
                        .backgroundColor(CENTER_ACCENT)
                        .opacity(this.activeIndex() === index ? 0 : 0.18)
                    }
                    SymbolGlyph(item.icon)
                      .fontSize(index === CENTER_INDEX ? 24 : (this.activeIndex() === index ? 23 : 17))
                      .fontColor([this.itemIconColor(index)])
                      .scale({ x: 1 + 0.14 * this.deformRatio(index), y: 1 + 0.14 * this.deformRatio(index) })
                      .translate({ y: -2 * this.deformRatio(index) })
                  }
                  .height(40)
                  .alignContent(Alignment.Center)

                  Text(item.title)
                    .fontSize(index === CENTER_INDEX ? 12 : 11)
                    .fontWeight(index === CENTER_INDEX ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.itemLabelColor(index))
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .onClick((): void => {
                  this.selectTab(index);
                })
              }, (item: GlassTabItem): string => item.title)
            }
            .width('100%')
            .height('100%')
            // 实测「图标行内容宽」→ 计算格宽（不含内缩，胶囊位置另加 BAR_CELL_INSET）
            .onAreaChange((_oldValue: Area, newValue: Area): void => {
              const w = Number(newValue.width);
              if (w > 0 && Math.abs(w - this.innerWidth) > 0.5) {
                this.innerWidth = w;
                if (!this.isDragging) {
                  this.indicatorX = this.cellCenter(this.selectedIndex);
                  this.pillScaleX = REST_SCALE;
                  this.pillScaleY = REST_SCALE;
                }
              }
            })
            .width('100%')
            .height('100%')
          }
          .width('100%')
          .height('100%')
          .padding({ left: BAR_CELL_INSET, right: BAR_CELL_INSET })
          .gesture(
            PanGesture({ direction: PanDirection.All })
              .onActionStart((): void => {
                this.isDragging = true;
                this.dragStartX = this.indicatorX;
                this.maxDragDist = 0;
                this.lastMoveX = this.indicatorX;
                this.lastMoveTime = Date.now();
                this.flingVelocity = 0;
              })
              .onActionUpdate((event: GestureEvent): void => {
                if (!this.isDragging || this.innerWidth <= 0) {
                  return;
                }
                const minC = this.cellCenter(0);
                const maxC = this.cellCenter(this.items.length - 1);
                let target = this.dragStartX + event.offsetX;
                target = Math.max(minC, Math.min(maxC, target));
                this.moveIndicator(target, curves.responsiveSpringMotion(0.32, 0.6));
                const now = Date.now();
                const dt = now - this.lastMoveTime;
                if (dt > 0) {
                  this.flingVelocity = (target - this.lastMoveX) / dt;
                }
                this.lastMoveX = target;
                this.lastMoveTime = now;
                const curDist = Math.abs(target - this.dragStartX);
                this.maxDragDist = Math.max(this.maxDragDist, curDist);
                this.updatePillStretch(this.maxDragDist, this.flingVelocity, event.offsetY);
              })
              .onActionEnd((): void => {
                this.isDragging = false;
                const idx = this.activeIndex();
                this.selectedIndex = idx;
                AppStorage.setOrCreate<number>('current_tab', idx);
                this.tabsController.changeIndex(idx);
                this.moveIndicator(this.cellCenter(idx), curves.springMotion(0.32, 0.6));
                this.resetPillStretch();
              })
          )
        }
        .width('100%')
        .height(this.barHeightVp())
      }
      .width('100%')
      .padding({ left: BAR_SIDE_MARGIN, right: BAR_SIDE_MARGIN, bottom: this.barBottomEdgeVp() })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_bg'))
    // 窗口已铺满整屏：两个方向都由本应用绘制，这样底部不会再露出窗口背景（深色下=黑条）。
    // 顶部状态栏的避让改由下方 Tabs 的内边距让出。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // 实测容器可用尺寸，据此推算栏高/底距/页面预留，避免机型硬编码
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      const h = Number(newValue.height);
      if (h > 0 && Math.abs(h - this.rootH) > 0.5) {
        this.rootH = h;
        this.publishBarClearance();
      }
    })
  }
}
