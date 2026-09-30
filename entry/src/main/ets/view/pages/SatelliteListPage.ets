import { SatelliteApp } from '../../common/SatelliteApp';
import { SatelliteDataSource } from '../../data/storage/SatelliteStore';
import { SatOrbitalData } from '../../domain/predict/OrbitalData';
import { promptAction, uiMaterial } from '@kit.ArkUI';
import { ISS_CATNUM } from '../../common/SatelliteApp';
import { SelectedSats } from '../../common/SelectedSats';
import { ENTER_SCALE, PRESS_IN_MS, PRESS_OUT_MS, PRESS_SCALE } from '../components/PressFx';
import { TAB_BAR_CLEARANCE } from '../../common/LayoutMetrics';

/** 查询串是否纯数字：只有纯数字才需要比 NORAD 编号。 */
function isDigits(q: string): boolean {
  if (q.length === 0) {
    return false;
  }
  for (let i = 0; i < q.length; i++) {
    const c = q.charCodeAt(i);
    if (c < 48 || c > 57) {
      return false;
    }
  }
  return true;
}

@Component
export struct SatelliteListPage {
  @State loading: boolean = false;
  @State selectedCount: number = 0;
  @State unselectedCount: number = 0;
  @StorageLink('selected_cats') selectedCats: number[] = [];
  @StorageProp('selected_version') @Watch('onSelectionChanged') selVersion: number = 0;
  @StorageLink('data_version') @Watch('onDataChanged') dataVersion: number = 0;

  @State searchVisible: boolean = false;
  @State searchQuery: string = '';
  @State searchResults: SatOrbitalData[] = [];
  @State pressedBtn: string = '';
  @State btnEntered: boolean = false;

  private app: SatelliteApp = SatelliteApp.getInstance();
  private scroller: Scroller = new Scroller();
  private selectedSource: SatelliteDataSource = new SatelliteDataSource([]);
  private unselectedSource: SatelliteDataSource = new SatelliteDataSource([]);
  private selectedArr: SatOrbitalData[] = [];
  private unselectedArr: SatOrbitalData[] = [];
  private selectedSet: Set<number> = new Set<number>();
  /** 名称预排序结果 + 小写名称索引，仅在数据变化时重建。 */
  private orderedAll: SatOrbitalData[] = [];
  private nameKeys: string[] = [];
  /** 本次选择变更由增量搬移处理，跳过 onSelectionChanged 的整表重建 */
  private suppressRefresh: boolean = false;

  aboutToAppear(): void {
    this.reloadAll();
    if (this.app.getStore().getAll().length === 0) {
      this.doAutoDownload();
    }
  }

  /** 卫星集变化（下载/导入）：重建排序与搜索索引后再刷新分组。 */
  onDataChanged(): void {
    this.reloadAll();
  }

  /** 选择集变化：无需重排，只要重新分组（增量路径会自行跳过）。 */
  onSelectionChanged(): void {
    if (this.suppressRefresh) {
      return;
    }
    this.refreshGroups();
  }

  private backToTop(): void {
    this.scroller.scrollEdge(Edge.Top);
  }

  /**
   * 一次性构建：按名称排序（用预计算的小写键做 < 比较，避免 localeCompare 的
   * ICU 开销）+ 与排序结果平行的小写名称数组，供搜索直接扫描、不再逐条 toLowerCase。
   */
  private buildIndex(): void {
    const all = this.app.getStore().getAll();
    const n = all.length;
    const keys: string[] = [];
    const order: number[] = [];
    for (let i = 0; i < n; i++) {
      keys.push(all[i].name.toLowerCase());
      order.push(i);
    }
    order.sort((a: number, b: number): number => {
      const ka = keys[a];
      const kb = keys[b];
      if (ka < kb) {
        return -1;
      }
      return ka > kb ? 1 : 0;
    });
    const arr: SatOrbitalData[] = [];
    const sortedKeys: string[] = [];
    for (let i = 0; i < n; i++) {
      const idx = order[i];
      arr.push(all[idx]);
      sortedKeys.push(keys[idx]);
    }
    this.orderedAll = arr;
    this.nameKeys = sortedKeys;
  }

  private reloadAll(): void {
    this.buildIndex();
    this.refreshGroups();
  }

  /**
   * 按「已选 / 未选」分组。
   * - 未选择：沿用名称预排序结果
   * - 已选择：按加入顺序（先选的在上，后选的追加到下面），顺序取自 selected_cats
   */
  private refreshGroups(): void {
    const set = new Set<number>();
    for (let i = 0; i < this.selectedCats.length; i++) {
      set.add(this.selectedCats[i]);
    }
    this.selectedSet = set;
    const others: SatOrbitalData[] = [];
    const byCat: Map<number, SatOrbitalData> = new Map<number, SatOrbitalData>();
    for (let i = 0; i < this.orderedAll.length; i++) {
      const s = this.orderedAll[i];
      if (set.has(s.catnum)) {
        byCat.set(s.catnum, s);
      } else {
        others.push(s);
      }
    }
    const selected: SatOrbitalData[] = [];
    for (let i = 0; i < this.selectedCats.length; i++) {
      const s = byCat.get(this.selectedCats[i]);
      if (s !== undefined) {
        selected.push(s);
      }
    }
    this.selectedArr = selected;
    this.unselectedArr = others;
    this.selectedSource.setData(selected);
    this.unselectedSource.setData(others);
    this.selectedCount = selected.length;
    this.unselectedCount = others.length;
  }

  /** 输入本身已按名称有序，这里只做「已选 / 未选」切分，保持各自有序。 */
  private splitBySelection(list: SatOrbitalData[]): SatOrbitalData[][] {
    const selected: SatOrbitalData[] = [];
    const others: SatOrbitalData[] = [];
    for (let i = 0; i < list.length; i++) {
      const s = list[i];
      if (this.selectedSet.has(s.catnum)) {
        selected.push(s);
      } else {
        others.push(s);
      }
    }
    return [selected, others];
  }

  /**
   * 选择/取消时走动画：让选中项从原位置飞到「已选择」分区（新选的落在该区末尾）。
   * 用增量搬移（add/delete 通知）而不是 setData 整表刷新，
   * 否则整个分区会在动画里重新挂载，表现为「列表项从上往下逐个淡入」。
   */
  private toggleSelected(catnum: number): void {
    const wasSelected = this.selectedSet.has(catnum);
    this.getUIContext().animateTo({ duration: 320, curve: Curve.Friction }, (): void => {
      this.suppressRefresh = true;
      SelectedSats.toggle(catnum);
      this.moveRowIncremental(catnum, wasSelected);
      this.suppressRefresh = false;
    });
  }

  /** 只搬动变化的那一项：从源分区删除 + 插入到目标分区，各通知一次。 */
  private moveRowIncremental(catnum: number, wasSelected: boolean): void {
    if (!wasSelected) {
      const ui = this.indexOfCat(this.unselectedArr, catnum);
      if (ui < 0) {
        return;
      }
      const item = this.unselectedArr[ui];
      this.unselectedArr.splice(ui, 1);
      this.unselectedSource.notifyDataDelete(ui);
      this.selectedArr.push(item);
      this.selectedSet.add(catnum);
      this.selectedSource.notifyDataAdd(this.selectedArr.length - 1);
    } else {
      const si = this.indexOfCat(this.selectedArr, catnum);
      if (si < 0) {
        return;
      }
      const item = this.selectedArr[si];
      this.selectedArr.splice(si, 1);
      this.selectedSource.notifyDataDelete(si);
      // 未选择区按名称升序，二分找到插入位置，保持有序不整表重建
      const ins = this.nameInsertIndex(this.unselectedArr, item.name.toLowerCase());
      this.unselectedArr.splice(ins, 0, item);
      this.selectedSet.delete(catnum);
      this.unselectedSource.notifyDataAdd(ins);
    }
    this.selectedCount = this.selectedArr.length;
    this.unselectedCount = this.unselectedArr.length;
  }

  private indexOfCat(list: SatOrbitalData[], catnum: number): number {
    for (let i = 0; i < list.length; i++) {
      if (list[i].catnum === catnum) {
        return i;
      }
    }
    return -1;
  }

  /** 在按小写名称升序排列的列表里，找 key 的插入位置。 */
  private nameInsertIndex(list: SatOrbitalData[], key: string): number {
    let lo = 0;
    let hi = list.length;
    while (lo < hi) {
      const mid = Math.floor((lo + hi) / 2);
      const mk = list[mid].name.toLowerCase();
      if (mk < key) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  private async doAutoDownload(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    try {
      const count = await this.app.downloadAndStore();
      try {
        await this.app.downloadTranspondersAndStore();
      } catch (e) {
        // optional
      }
      this.reloadAll();
      if (count > 0) {
        const iss = this.app.getStore().getByCatnum(ISS_CATNUM);
        if (iss !== null && !SelectedSats.isSelected(ISS_CATNUM)) {
          SelectedSats.toggle(ISS_CATNUM);
        }
      }
    } catch (e) {
      // silent
    } finally {
      this.loading = false;
    }
  }

  private async doDownload(): Promise<void> {
    this.loading = true;
    try {
      const count = await this.app.downloadAndStore();
      try {
        await this.app.downloadTranspondersAndStore();
      } catch (e) {
        // optional
      }
      this.reloadAll();
      promptAction.showToast({ message: `已下载 ${count} 颗卫星` });
    } catch (e) {
      promptAction.showToast({ message: '下载失败，请检查网络' });
    } finally {
      this.loading = false;
    }
  }

  private async doImport(): Promise<void> {
    try {
      const count = await this.app.importAndStore(getContext(this));
      if (count < 0) {
        return;
      }
      this.reloadAll();
      promptAction.showToast({ message: `已导入 ${count} 颗卫星` });
    } catch (e) {
      promptAction.showToast({ message: '导入失败' });
    }
  }

  /** 🔍 弹出搜索框 */
  private openSearch(): void {
    this.searchQuery = '';
    this.searchResults = [];
    this.searchVisible = true;
  }

  /**
   * 直接扫描预排序 + 预小写的结果集：不再逐条 toLowerCase()，也顺带保证
   * 命中结果已按名称有序（无需再排序）；仅纯数字查询才比 NORAD 编号。
   */
  private applySearchQuery(): void {
    const q = this.searchQuery.trim().toLowerCase();
    if (q.length === 0) {
      this.searchResults = [];
      return;
    }
    if (this.orderedAll.length === 0) {
      this.buildIndex();
    }
    const numeric = isDigits(q);
    const arr = this.orderedAll;
    const keys = this.nameKeys;
    const list: SatOrbitalData[] = [];
    for (let i = 0; i < arr.length; i++) {
      const nameHit = keys[i].indexOf(q) >= 0;
      const numHit = numeric && String(arr[i].catnum).indexOf(q) >= 0;
      if (nameHit || numHit) {
        list.push(arr[i]);
        if (list.length >= 50) {
          break;
        }
      }
    }
    const groups = this.splitBySelection(list);
    this.searchResults = groups[0].concat(groups[1]);
  }

  private datasetColor(item: SatOrbitalData): ResourceColor {
    return item.isDeepSpace ? '#E67E22' : '#2ECC71';
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        if (this.selectedCount === 0 && this.unselectedCount === 0) {
          Column({ space: 12 }) {
            Text($r('app.string.empty_hint'))
              .fontColor($r('app.color.color_text_secondary'))
              .fontSize(14)
              .textAlign(TextAlign.Center)
            Button('下载数据')
              .onClick((): void => {
                this.doDownload()
              })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8, scroller: this.scroller }) {
            if (this.selectedCount > 0) {
              ListItemGroup({
                header: this.sectionHeader('已选择', this.selectedCount),
                space: 8
              }) {
                LazyForEach(this.selectedSource, (item: SatOrbitalData) => {
                  ListItem() {
                    this.satRow(item)
                  }
                }, (item: SatOrbitalData): string => {
                  return String(item.catnum)
                })
              }
            }
            if (this.unselectedCount > 0) {
              ListItemGroup({
                header: this.sectionHeader('未选择', this.unselectedCount),
                space: 8
              }) {
                LazyForEach(this.unselectedSource, (item: SatOrbitalData) => {
                  ListItem() {
                    this.satRow(item)
                  }
                }, (item: SatOrbitalData): string => {
                  return String(item.catnum)
                })
              }
            }
            // 末尾占位项：给滚动内容留出胶囊栏的空间（放在内容里，而不是给 List 加 padding，
            // 否则会把 List 可视区缩小、底部永远空一条）
            ListItem() {
              Column().width('100%').height(TAB_BAR_CLEARANCE)
            }
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 14, right: 14 })
          .sticky(StickyStyle.Header)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.color_bg'))

      // 右下角圆形悬浮按钮
      this.floatingButtons()
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: 8 })
    .bindSheet($$this.searchVisible, this.searchSheetBuilder(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE]
    })
  }

  @Builder
  private searchSheetBuilder() {
    Column({ space: 10 }) {
      Text('搜索卫星并选择要跟踪的')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.color_text'))

      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索名称或 NORAD 编号', text: this.searchQuery })
          .layoutWeight(1)
          .height(36)
          .borderRadius(8)
          .fontSize(13)
          .onChange((value: string): void => {
            this.searchQuery = value;
            this.applySearchQuery();
          })
      }
      .width('100%')

      if (this.searchResults.length === 0) {
        Text('输入关键词搜索卫星')
          .fontSize(13)
          .fontColor($r('app.color.color_text_secondary'))
          .width('100%')
          .padding({ top: 20, bottom: 20 })
          .textAlign(TextAlign.Center)
      } else {
        List({ space: 6 }) {
          ForEach(this.searchResults, (s: SatOrbitalData) => {
            ListItem() {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text(s.name)
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.color_text'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`NORAD ${s.catnum} · ${s.isDeepSpace ? '深空' : '近地'}`)
                    .fontSize(11)
                    .fontColor($r('app.color.color_text_secondary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Toggle({ type: ToggleType.Switch, isOn: this.isSelectedLocal(s.catnum) })
                  .selectedColor($r('app.color.color_primary'))
                  .onChange((isOn: boolean): void => {
                    if (isOn !== this.isSelectedLocal(s.catnum)) {
                      this.toggleSelected(s.catnum)
                    }
                  })
              }
              .width('100%')
              .padding(8)
              .backgroundColor($r('app.color.color_card'))
              .borderRadius(8)
            }
          }, (s: SatOrbitalData): string => {
            return String(s.catnum)
          })
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private floatingButtons() {
    Column({ space: 14 }) {
      this.floatButton($r('sys.symbol.arrow_up_to_line'), '返回顶部', 'top')
      this.floatButton($r('sys.symbol.magnifyingglass'), '搜索', 'search')
    }
    .alignItems(HorizontalAlign.End)
    .margin({ right: 14, bottom: TAB_BAR_CLEARANCE })
    .onAppear((): void => {
      this.getUIContext().animateTo({ duration: 320, curve: Curve.Friction }, (): void => {
        this.btnEntered = true;
      });
    })
  }

  /** 与底部任务栏同款玻璃风格：磨砂背板 + 主题色 Symbol + 按压缩放。 */
  @Builder
  private floatButton(icon: Resource, labelTxt: string, action: string) {
    Column({ space: 3 }) {
      Column() {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([$r('app.color.color_primary')])
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.color_card'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THIN,
        applyShadow: true,
        interactive: true
      }))
      .shadow({ radius: 12, color: '#26000000', offsetY: 3 })
      .opacity(0.94)
      .scale({ x: this.pressScale(`fab-${action}`), y: this.pressScale(`fab-${action}`) })
      .onTouch((event: TouchEvent): void => {
        this.onBtnTouch(`fab-${action}`, event);
      })
      .onClick((): void => {
        if (action === 'top') {
          this.backToTop()
        } else if (action === 'update') {
          this.doDownload()
        } else if (action === 'import') {
          this.doImport()
        } else {
          this.openSearch()
        }
      })
      Text(labelTxt).fontSize(9).fontColor($r('app.color.color_text_secondary'))
    }
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private sectionHeader(title: string, count: number) {
    Row({ space: 6 }) {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.color_text'))
      Text(`${count}`)
        .fontSize(12)
        .fontColor($r('app.color.color_text_secondary'))
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 10, bottom: 6 })
    .backgroundColor($r('app.color.color_bg'))
  }

  @Builder
  private satRow(item: SatOrbitalData) {
    Row({ space: 12 }) {
      Column() {
        Text(item.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_text'))
          // 名字过长自动换行显示（最多两行，再长才省略）
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 8 }) {
          Text(`NORAD ${item.catnum}`)
            .fontSize(12)
            .fontColor($r('app.color.color_text_secondary'))
          Text(item.isDeepSpace ? '深空' : '近地')
            .fontSize(12)
            .fontColor(this.datasetColor(item))
        }
        .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.isSelectedLocal(item.catnum) })
        .selectedColor($r('app.color.color_primary'))
        .onChange((isOn: boolean): void => {
          if (isOn !== this.isSelectedLocal(item.catnum)) {
            this.toggleSelected(item.catnum)
          }
        })

      Row()
        .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(12)
    // 共享元素转场：同一颗星在「未选择」消失、「已选择」出现时按位置插值飞行
    .geometryTransition(`sat-${item.catnum}`)
    .transition(TransitionEffect.OPACITY)
  }

  private isSelectedLocal(catnum: number): boolean {
    return this.selectedCats.indexOf(catnum) >= 0;
  }

  // ---- 悬浮按钮动画（与底栏/其他页同一套）----

  /** 入场：整组按钮从 0.86 回弹到 1；按压：当前按钮收到 0.9 再回弹。 */
  private pressScale(key: string): number {
    const base = this.btnEntered ? 1 : ENTER_SCALE;
    return this.pressedBtn === key ? base * PRESS_SCALE : base;
  }

  private onBtnTouch(key: string, event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.getUIContext().animateTo({ duration: PRESS_IN_MS, curve: Curve.Friction }, (): void => {
        this.pressedBtn = key;
      });
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.getUIContext().animateTo({ duration: PRESS_OUT_MS, curve: Curve.Friction }, (): void => {
        if (this.pressedBtn === key) {
          this.pressedBtn = '';
        }
      });
    }
  }
}