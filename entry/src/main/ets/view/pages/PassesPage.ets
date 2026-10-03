import { SatelliteApp } from '../../common/SatelliteApp';
import { SelectedSats } from '../../common/SelectedSats';
import { AppSettings, PassSortMode } from '../../common/AppSettings';
import { SAT_COLORS } from '../../common/SatColors';
import { SatPassEvent } from '../../domain/predict/SatPassFinder';
import { PassCache } from '../../domain/predict/PassCache';
import { PassDetailSheet, PassDetailPayload } from '../components/PassDetailSheet';
import { Logger } from '../../common/Logger';
import { KEY_BAR_CLEARANCE, TAB_BAR_CLEARANCE } from '../../common/LayoutMetrics';

const TAB_PASSES = 2;
/** 过境页视图状态：加载中 / 有数据 / 确实为空（避免把"还没算完"当成"无数据"） */
enum PassViewState {
  LOADING = 0,
  READY = 1,
  EMPTY = 2
}
/** 切到过境页/启动后延后多久开算（先让首屏与入场动画跑完） */
const PASS_START_DELAY_MS = 200;
/** 每补算一颗星让出多久：给渲染留帧，选星多时也不会长阻塞 */
const PASS_YIELD_MS = 24;
/** 每补算多少颗星才提交一次 UI（合并重绘） */
const PASS_UI_COMMIT_EVERY = 5;
const NOW_REFRESH_MS = 1000;

class PassSat {
  catnum: number;
  name: string;
  color: string;
  passes: SatPassEvent[];

  constructor(catnum: number, name: string, color: string, passes: SatPassEvent[]) {
    this.catnum = catnum;
    this.name = name;
    this.color = color;
    this.passes = passes;
  }
}

class FlatPass {
  catnum: number;
  name: string;
  color: string;
  pass: SatPassEvent;

  constructor(catnum: number, name: string, color: string, pass: SatPassEvent) {
    this.catnum = catnum;
    this.name = name;
    this.color = color;
    this.pass = pass;
  }
}

/** 独立子组件：过境进度条。父级每秒刷新 nowTs 传入 @Prop，保证列表项不重建也能更新。 */
@Component
export struct PassProgressBar {
  @Prop nowTs: number = 0;
  @Prop aosTime: number = 0;
  @Prop losTime: number = 0;
  @Prop showLabel: boolean = false;

  private progress(): number {
    const dur = Math.max(1, this.losTime - this.aosTime);
    return Math.max(0, Math.min(1, (this.nowTs - this.aosTime) / dur));
  }

  build() {
    Row({ space: 8 }) {
      if (this.showLabel) {
        Text('● 过境中')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor('#E6A23C')
      }
      Progress({ value: Math.round(this.progress() * 100), total: 100, type: ProgressType.Linear })
        .width('100%')
        .layoutWeight(1)
        .color('#E6A23C')
        .backgroundColor('#3D3D3D')
        .height(6)
      Text(`${Math.round(this.progress() * 100)}%`)
        .fontSize(11)
        .fontColor($r('app.color.color_text_secondary'))
    }
    .width('100%')
  }
}

@Component
export struct PassesPage {
  @State groups: PassSat[] = [];
  @State flatPasses: FlatPass[] = [];
  @StorageLink('selected_version') @Watch('recompute') selVersion: number = 0;
  @StorageLink('data_version') @Watch('recompute') dataVersion: number = 0;
  @StorageLink('settings_window_hours') @Watch('recompute') windowHours: number = 24;
  @StorageLink('settings_min_elevation') @Watch('recompute') minElevation: number = 5;
  @StorageLink('settings_pass_sort') @Watch('recompute') sortMode: number = PassSortMode.BY_SATELLITE;
  @StorageLink('station_latitude') @Watch('recompute') stationLat: number = 48.2;
  @StorageLink('station_longitude') @Watch('recompute') stationLon: number = 16.37;
  @StorageLink('station_altitude') @Watch('recompute') stationAlt: number = 0;
  @StorageProp('current_tab') @Watch('onTabChanged') currentTab: number = TAB_PASSES;

  @State showDetail: boolean = false;
  @State detailPayload: PassDetailPayload = new PassDetailPayload();
  @State detailOpenSeq: number = 0;
  @State trackCount: number = 0;
  @State nowTs: number = Date.now();
  @State nextPass: FlatPass | null = null;
  /** 视图状态：区分"加载中/有数据/确实为空" */
  @State viewState: PassViewState = PassViewState.LOADING;
  /** 底部预留（由 Index 按栏高+导航条避让算出后发布） */
  @StorageProp(KEY_BAR_CLEARANCE) barClearance: number = TAB_BAR_CLEARANCE;

  private dirty: boolean = false;
  private app: SatelliteApp = SatelliteApp.getInstance();
  private nowTimerId: number = -1;
  /** 已排程的重算定时器 / 计算序号（用于作废过期计算） */
  private pendingCalcId: number = -1;
  private computeSeq: number = 0;

  aboutToAppear(): void {
    this.dirty = false;
    this.scheduleCompute();
    this.nowTimerId = setInterval((): void => {
      this.nowTs = Date.now();
      this.refreshNextPass();
    }, NOW_REFRESH_MS);
  }

  aboutToDisappear(): void {
    if (this.nowTimerId >= 0) {
      clearInterval(this.nowTimerId);
      this.nowTimerId = -1;
    }
    if (this.pendingCalcId >= 0) {
      clearTimeout(this.pendingCalcId);
      this.pendingCalcId = -1;
    }
  }

  /** 本页不可见时只记脏标记，避免在卫星页点开关就同步跑全量过境预报。 */
  recompute(): void {
    if (this.currentTab !== TAB_PASSES) {
      this.dirty = true;
      return;
    }
    this.dirty = false;
    this.scheduleCompute();
  }

  onTabChanged(): void {
    if (this.currentTab === TAB_PASSES) {
      if (this.dirty) {
        this.dirty = false;
        this.scheduleCompute();
      }
    } else if (this.pendingCalcId >= 0) {
      // 还没开算就切走了：取消，避免在不可见时白算
      clearTimeout(this.pendingCalcId);
      this.pendingCalcId = -1;
      this.dirty = true;
    }
  }

  /**
   * 延后一点再开算：启动/切页时先让首屏与入场动画跑完，避免重算抢占主线程。
   * 已排程时不重复排（到点后 doRecompute 会重新读取最新状态）。
   */
  private scheduleCompute(): void {
    if (this.pendingCalcId >= 0) {
      return;
    }
    this.pendingCalcId = setTimeout((): void => {
      this.pendingCalcId = -1;
      if (this.currentTab !== TAB_PASSES) {
        this.dirty = true;
        return;
      }
      const seq = ++this.computeSeq;
      this.doRecompute(seq);
    }, PASS_START_DELAY_MS);
  }

  /**
   * 重算：命中缓存的星直接用，只有没缓存的才逐颗补算并让帧。
   * 选的星多时不会一次性长阻塞，列表会逐步补齐。
   */
  private async doRecompute(seq: number): Promise<void> {
    const cats = SelectedSats.getCats();
    this.trackCount = cats.length;
    this.nowTs = Date.now();
    const cache = PassCache.getInstance();
    if (cats.length === 0) {
      this.groups = [];
      this.flatPasses = [];
      this.viewState = this.app.hasStoreLoaded() ? PassViewState.EMPTY : PassViewState.LOADING;
      this.refreshNextPass();
      return;
    }
    const store = this.app.getStore();
    const station = AppSettings.getStation();
    cache.prepare(this.dataVersion);
    if (this.viewState !== PassViewState.READY) {
      this.viewState = PassViewState.LOADING;
    }
    // 先用已有缓存渲染一版（切页/改窗口/改排序基本瞬时）；计算中暂无结果时保留旧数据
    this.publishGroups(cats, cache, false);
    for (let i = 0; i < cats.length; i++) {
      if (seq !== this.computeSeq) {
        return;
      }
      const cat = cats[i];
      if (cache.has(cat)) {
        continue;
      }
      const satData = store.getByCatnum(cat);
      if (satData === null) {
        cache.markMissing(cat);
        continue;
      }
      cache.computeOne(cat, satData, station, this.nowTs);
      await PassesPage.yieldFrame();
      if (seq !== this.computeSeq) {
        return;
      }
      // 每 5 颗才提交一次 UI（§18/§19：避免逐颗重绘），最后一颗一定提交
      if ((i + 1) % PASS_UI_COMMIT_EVERY === 0 || i === cats.length - 1) {
        this.publishGroups(cats, cache, false);
      }
    }
    // 最终提交前再确认没被更新的请求取代（防止旧结果覆盖新结果）
    if (seq !== this.computeSeq) {
      return;
    }
    this.publishGroups(cats, cache, true);
  }

  /**
   * 把缓存结果整理成列表数据。
   * 同时维护「按卫星」和「按时间」两份列表：排序方式切换时立即可用，
   * 不会出现「切换后当前列表为空 → 闪一下无数据」。
   * [isFinal] 为 false 表示还在补算：此时若暂无结果则保留旧数据不提交。
   */
  private publishGroups(cats: number[], cache: PassCache, isFinal: boolean): void {
    const satList: PassSat[] = [];
    for (let i = 0; i < cats.length; i++) {
      const cat = cats[i];
      if (!cache.has(cat)) {
        continue;
      }
      satList.push(new PassSat(cat, cache.nameOf(cat), SAT_COLORS[i % SAT_COLORS.length], cache.passesOf(cat)));
    }
    const hasData = satList.length > 0;
    if (!hasData && !isFinal && this.hasRenderedData()) {
      // 还在计算、暂无结果：保留上一次的列表，避免「旧数据 → 无数据 → 新数据」
      return;
    }

    const flat: FlatPass[] = [];
    for (let i = 0; i < satList.length; i++) {
      const s = satList[i];
      for (let j = 0; j < s.passes.length; j++) {
        flat.push(new FlatPass(s.catnum, s.name, s.color, s.passes[j]));
      }
    }
    flat.sort((a: FlatPass, b: FlatPass): number => {
      const ta = this.distanceToPass(a.pass);
      const tb = this.distanceToPass(b.pass);
      if (ta !== tb) {
        return ta - tb;
      }
      return a.pass.aosTime - b.pass.aosTime;
    });
    satList.sort((a: PassSat, b: PassSat): number => a.name.localeCompare(b.name));
    // 两份列表都保持最新，排序切换无需等待重算
    this.groups = satList;
    this.flatPasses = flat;

    if (hasData) {
      this.viewState = PassViewState.READY;
    } else if (!this.app.hasStoreLoaded()) {
      this.viewState = PassViewState.LOADING;
    } else {
      this.viewState = isFinal ? PassViewState.EMPTY : PassViewState.LOADING;
    }
    this.refreshNextPass();
  }

  /** 当前是否已渲染出内容（用于判断"能不能保留旧数据"）。 */
  private hasRenderedData(): boolean {
    return this.groups.length > 0 || this.flatPasses.length > 0;
  }

  /** 让帧：把主线程还给渲染，避免连续补算造成卡顿。 */
  private static yieldFrame(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout((): void => {
        resolve();
      }, PASS_YIELD_MS);
    });
  }

  /** 找出距离现在最近的一次未开始过境，用于头部倒计时。 */
  private refreshNextPass(): void {
    const limit = this.nowTs + this.windowHours * 3600000;
    let best: FlatPass | null = null;
    if (this.flatPasses.length > 0) {
      for (let i = 0; i < this.flatPasses.length; i++) {
        const f = this.flatPasses[i];
        if (f.pass.aosTime > this.nowTs && f.pass.aosTime < limit &&
          f.pass.maxElevationDeg >= this.minElevation &&
          (best === null || f.pass.aosTime < best.pass.aosTime)) {
          best = f;
        }
      }
    } else {
      for (let i = 0; i < this.groups.length; i++) {
        const g = this.groups[i];
        for (let j = 0; j < g.passes.length; j++) {
          const p = g.passes[j];
          if (p.aosTime > this.nowTs && p.aosTime < limit &&
            p.maxElevationDeg >= this.minElevation &&
            (best === null || p.aosTime < best.pass.aosTime)) {
            best = new FlatPass(g.catnum, g.name, g.color, p);
          }
        }
      }
    }
    this.nextPass = best;
  }

  private countdownText(aos: number): string {
    const totalSec = Math.floor(Math.max(0, aos - this.nowTs) / 1000);
    const h = Math.floor(totalSec / 3600);
    const m = Math.floor((totalSec % 3600) / 60);
    const s = totalSec % 60;
    if (h > 0) {
      return `${h}小时${m}分`;
    }
    if (m > 0) {
      return `${m}分${s.toString().padStart(2, '0')}秒`;
    }
    return `${s}秒`;
  }

  /** 距离过境时间的远近：正在过境=0，否则为距 AOS 的毫秒数。 */
  private distanceToPass(p: SatPassEvent): number {
    if (this.isInPass(p)) {
      return 0;
    }
    return Math.max(0, p.aosTime - this.nowTs);
  }

  private isInPass(p: SatPassEvent): boolean {
    return this.nowTs >= p.aosTime && this.nowTs <= p.losTime;
  }

  /** 该卫星当前是否有正在进行的过境（用于列表行/卡片突出显示）。 */
  private satInPass(passes: SatPassEvent[]): boolean {
    for (let i = 0; i < passes.length; i++) {
      if (this.isInPass(passes[i])) {
        return true;
      }
    }
    return false;
  }

  private passProgress(p: SatPassEvent): number {
    if (!this.isInPass(p)) {
      return 0;
    }
    const dur = Math.max(1, p.losTime - p.aosTime);
    const v = (this.nowTs - p.aosTime) / dur;
    return Math.max(0, Math.min(1, v));
  }

  private openDetail(catnum: number, pass: SatPassEvent, color: string): void {
    this.detailOpenSeq++;
    const seq = this.detailOpenSeq;
    const payload = PassDetailSheet.buildPayload(catnum, pass, color);
    this.detailPayload = payload;
    this.showDetail = true;
    Logger.debug('PassOpen', `seq=${seq} cat=${catnum} name=${payload.name} show=${this.showDetail}`);
    if (!payload.hasTransponders) {
      this.waitForTransponders(catnum, pass, color, seq, 0);
    }
  }

  private waitForTransponders(catnum: number, pass: SatPassEvent, color: string, seq: number,
                              attempt: number): void {
    if (attempt >= 8) {
      return;
    }
    setTimeout((): void => {
      if (seq !== this.detailOpenSeq) {
        return;
      }
      const fresh = PassDetailSheet.buildPayload(catnum, pass, color);
      if (fresh.hasTransponders) {
        this.detailPayload = fresh;
      } else {
        this.waitForTransponders(catnum, pass, color, seq, attempt + 1);
      }
    }, 300 * (attempt + 1));
  }

  @Builder
  detailSheetBuilder() {
    if (this.showDetail) {
      if (this.detailOpenSeq % 2 === 0) {
        PassDetailSheet({
          detail: this.detailPayload
        })
      } else {
        PassDetailSheet({
          detail: this.detailPayload
        })
      }
    } else {
      Column() {
      }
      .width('100%')
      .height(100)
    }
  }

  build() {
    Column() {
      this.headerBar()
      // 三态显示：加载中 / 有数据 / 确实为空（"数据还没算完"不再冒充"无数据"）
      if (this.viewState === PassViewState.READY) {
        if (this.sortMode === PassSortMode.BY_SATELLITE) {
          this.satelliteView()
        } else {
          this.flatTimeView()
        }
      } else if (this.viewState === PassViewState.LOADING) {
        this.loadingView()
      } else {
        this.emptyView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_bg'))
    .bindSheet($$this.showDetail, this.detailSheetBuilder(), {
      detents: [SheetSize.LARGE],
      showClose: false
    })
  }

  private passVisible(p: SatPassEvent): boolean {
    return p.losTime > this.nowTs &&
      p.aosTime < this.nowTs + this.windowHours * 3600000 &&
      p.maxElevationDeg >= this.minElevation;
  }

  private countVisible(list: SatPassEvent[]): number {
    let n = 0;
    for (let i = 0; i < list.length; i++) {
      if (this.passVisible(list[i])) {
        n++;
      }
    }
    return n;
  }

  private visibleFlatCount(): number {
    let n = 0;
    for (let i = 0; i < this.flatPasses.length; i++) {
      if (this.passVisible(this.flatPasses[i].pass)) {
        n++;
      }
    }
    return n;
  }

  @Builder
  private headerBar() {
    Column({ space: 8 }) {
      Row() {
        Text('过境预报').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.color_text'))
        Blank()
        Text(`仰角>=${this.minElevation}deg · ${this.windowHours}h · ${this.trackCount}星`)
          .fontSize(11)
          .fontColor($r('app.color.color_text_secondary'))
      }
      .width('100%')

      Row({ space: 6 }) {
        Text('按卫星')
          .fontSize(13)
          .fontWeight(this.sortMode === PassSortMode.BY_SATELLITE ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.sortMode === PassSortMode.BY_SATELLITE ? '#FFFFFF' : $r('app.color.color_text_secondary'))
          .backgroundColor(this.sortMode === PassSortMode.BY_SATELLITE ? $r('app.color.color_primary') : $r('app.color.color_card'))
          .borderRadius(16)
          .padding({ left: 16, right: 16, top: 5, bottom: 5 })
          .onClick((): void => {
            // 切换排列方式：胶囊着色的过渡 + 列表交叉转场都在同一动画里
            this.getUIContext().animateTo({ duration: 320, curve: Curve.Friction }, (): void => {
              this.sortMode = PassSortMode.BY_SATELLITE
            });
          })
        Text('按时间')
          .fontSize(13)
          .fontWeight(this.sortMode === PassSortMode.BY_TIME ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.sortMode === PassSortMode.BY_TIME ? '#FFFFFF' : $r('app.color.color_text_secondary'))
          .backgroundColor(this.sortMode === PassSortMode.BY_TIME ? $r('app.color.color_primary') : $r('app.color.color_card'))
          .borderRadius(16)
          .padding({ left: 16, right: 16, top: 5, bottom: 5 })
          .onClick((): void => {
            this.getUIContext().animateTo({ duration: 320, curve: Curve.Friction }, (): void => {
              this.sortMode = PassSortMode.BY_TIME
            });
          })
      }
      .width('100%')

      if (this.nextPass !== null) {
        Column({ space: 5 }) {
          Row({ space: 8 }) {
            Circle({ width: 8, height: 8 }).fill(this.nextPass.color)
            Text('下次过境')
              .fontSize(11)
              .fontColor($r('app.color.color_text_secondary'))
            Text(this.nextPass.name)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.nextPass.color as ResourceColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(this.countdownText(this.nextPass.pass.aosTime))
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.color_primary'))
          }
          .width('100%')

          // 更详细的信息：起止时刻 + 各自方位角、最高仰角、时长、卫星高度
          Row({ space: 12 }) {
            Text(`AOS ${this.clock(this.nextPass.pass.aosTime)} · 方位 ${this.nextPass.pass.aosAzimuth.toFixed(0)}°`)
              .fontSize(11)
              .fontColor($r('app.color.color_text_secondary'))
            Text(`LOS ${this.clock(this.nextPass.pass.losTime)} · 方位 ${this.nextPass.pass.losAzimuth.toFixed(0)}°`)
              .fontSize(11)
              .fontColor($r('app.color.color_text_secondary'))
          }
          .width('100%')

          Row({ space: 12 }) {
            Text(`最高仰角 ${this.nextPass.pass.maxElevationDeg.toFixed(0)}°`)
              .fontSize(11)
              .fontColor($r('app.color.color_text'))
            Text(`持续 ${Math.round(this.nextPass.pass.durationMillis / 60000)} min`)
              .fontSize(11)
              .fontColor($r('app.color.color_text_secondary'))
            Text(`星高 ${this.nextPass.pass.altitudeKm.toFixed(0)} km`)
              .fontSize(11)
              .fontColor($r('app.color.color_text_secondary'))
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.color_card'))
        .borderRadius(8)
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 6 })
  }

  @Builder
  private loadingView() {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(26)
        .height(26)
        .color($r('app.color.color_primary'))
      Text('正在加载卫星数据…')
        .fontSize(13)
        .fontColor($r('app.color.color_text_secondary'))
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private emptyView() {
    Column({ space: 10 }) {
      Text('暂无过境数据')
        .fontSize(15)
        .fontColor($r('app.color.color_text'))
      Text('请在“卫星”标签页点选要跟踪的卫星')
        .fontSize(13)
        .fontColor($r('app.color.color_text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private satelliteView() {
    Scroll() {
      Column({ space: 14 }) {
        ForEach(this.groups, (g: PassSat) => {
          this.satCard(g)
        }, (g: PassSat): string => {
          return String(g.catnum)
        })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: this.barClearance })
    }
    .layoutWeight(1)
    .width('100%')
    // 排列方式切换：整体交叉淡入 + 上浮
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 })))
  }

  @Builder
  private flatTimeView() {
    Scroll() {
      Column({ space: 10 }) {
        ForEach(this.flatPasses, (f: FlatPass) => {
          if (this.passVisible(f.pass)) {
            this.flatRow(f)
          }
        }, (f: FlatPass): string => {
          return `${f.catnum}-${f.pass.aosTime}`
        })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: this.barClearance })
    }
    .layoutWeight(1)
    .width('100%')
    // 排列方式切换：整体交叉淡入 + 上浮
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 })))
  }

  @Builder
  private satCard(g: PassSat) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(g.name)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.color_text'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.satInPass(g.passes)) {
          // 正在过境：卡片标题旁给一个醒目徽标
          Text('● 过境中')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_primary'))
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .borderRadius(6)
            .borderWidth(1)
            .borderColor($r('app.color.color_primary'))
        }
        Text(`NORAD ${g.catnum}`)
          .fontSize(11)
          .fontColor(g.color as ResourceColor)
      }
      .width('100%')

      if (this.countVisible(g.passes) === 0) {
        Text(`近 ${this.windowHours}h 无达标过境`)
          .fontSize(12)
          .fontColor($r('app.color.color_text_secondary'))
          .width('100%')
      } else {
        ForEach(g.passes, (p: SatPassEvent) => {
          if (this.passVisible(p)) {
            this.passRow(g.catnum, p, g.color)
          }
        }, (p: SatPassEvent): string => {
          return String(p.aosTime)
        })
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(12)
    // 正在过境的卫星卡片描边强调
    .borderWidth(this.satInPass(g.passes) ? 1.5 : 0)
    .borderColor($r('app.color.color_primary'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private passRow(catnum: number, p: SatPassEvent, color: string) {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(this.dateLabel(p.aosTime))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(color as ResourceColor)
          Text(`AOS ${this.clock(p.aosTime)} → LOS ${this.clock(p.losTime)}`)
            .fontSize(12)
            .fontColor($r('app.color.color_text'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: 2 }) {
          Text(`最高 ${p.maxElevationDeg.toFixed(0)}°`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(color as ResourceColor)
          Text(`时长 ${Math.round(p.durationMillis / 60000)} min`)
            .fontSize(11)
            .fontColor($r('app.color.color_text_secondary'))
        }
        .alignItems(HorizontalAlign.End)

        Text('>')
          .fontSize(18)
          .fontColor($r('app.color.color_text_secondary'))
      }
      .width('100%')

      if (this.isInPass(p)) {
        PassProgressBar({
          nowTs: this.nowTs,
          aosTime: p.aosTime,
          losTime: p.losTime,
          showLabel: true
        })
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor($r('app.color.color_bg'))
    .borderRadius(8)
    // 正在过境的这一条：描边 + 更亮的主色强调
    .borderWidth(this.isInPass(p) ? 1.5 : 0)
    .borderColor($r('app.color.color_primary'))
    .onClick((): void => {
      this.openDetail(catnum, p, color)
    })
  }

  @Builder
  private flatRow(f: FlatPass) {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(this.dateLabel(f.pass.aosTime))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(f.color as ResourceColor)
          Text(`${f.name}`)
            .fontSize(12)
            .fontColor($r('app.color.color_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: 2 }) {
          Text(this.clock(f.pass.aosTime))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text'))
          Text(`最高 ${f.pass.maxElevationDeg.toFixed(0)}°`)
            .fontSize(11)
            .fontColor(f.color as ResourceColor)
        }
        .alignItems(HorizontalAlign.End)

        Text('>')
          .fontSize(18)
          .fontColor($r('app.color.color_text_secondary'))
      }
      .width('100%')

      if (this.isInPass(f.pass)) {
        PassProgressBar({
          nowTs: this.nowTs,
          aosTime: f.pass.aosTime,
          losTime: f.pass.losTime,
          showLabel: true
        })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(10)
    // 正在过境的这一条：描边强调
    .borderWidth(this.isInPass(f.pass) ? 1.5 : 0)
    .borderColor($r('app.color.color_primary'))
    .onClick((): void => {
      this.openDetail(f.catnum, f.pass, f.color)
    })
  }

  private dateLabel(millis: number): string {
    const d = new Date(millis);
    const today = new Date();
    const startOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
    const startOfPass = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    const dayDiff = Math.round((startOfPass - startOfToday) / 86400000);
    let rel = '';
    if (dayDiff === 0) {
      rel = '今天';
    } else if (dayDiff === 1) {
      rel = '明天';
    } else if (dayDiff === 2) {
      rel = '后天';
    }
    const dateStr = `${d.getMonth() + 1}月${d.getDate()}日`;
    return rel === '' ? dateStr : `${rel} ${dateStr}`;
  }

  private clock(millis: number): string {
    const d = new Date(millis);
    const hh = d.getHours().toString().padStart(2, '0');
    const mm = d.getMinutes().toString().padStart(2, '0');
    return `${hh}:${mm}`;
  }
}