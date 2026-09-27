import { SatelliteApp } from '../../common/SatelliteApp';
import { SatelliteDataSource } from '../../data/storage/SatelliteStore';
import { SatOrbitalData } from '../../domain/predict/OrbitalData';
import { promptAction } from '@kit.ArkUI';
import { ISS_CATNUM } from '../../common/SatelliteApp';
import { SelectedSats } from '../../common/SelectedSats';

@Component
export struct SatelliteListPage {
  @State dataSource: SatelliteDataSource = new SatelliteDataSource([]);
  @State loading: boolean = false;
  @State showingAll: SatOrbitalData[] = [];
  @State selectedCount: number = 0;
  @StorageLink('selected_cats') selectedCats: number[] = [];
  @StorageProp('selected_version') @Watch('onSelectionChanged') selVersion: number = 0;

  @State searchVisible: boolean = false;
  @State searchQuery: string = '';
  @State searchResults: SatOrbitalData[] = [];

  private app: SatelliteApp = SatelliteApp.getInstance();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.refreshList();
    if (this.app.getStore().getAll().length === 0) {
      this.doAutoDownload();
    }
  }

  onSelectionChanged(): void {
    this.refreshList();
  }

  private backToTop(): void {
    this.scroller.scrollEdge(Edge.Top);
  }

  private sortAlphabetical(list: SatOrbitalData[]): SatOrbitalData[] {
    list.sort((a: SatOrbitalData, b: SatOrbitalData): number => a.name.localeCompare(b.name));
    return list;
  }

  /** 已选置顶（已选项内也按名称排序），其余按首字母。 */
  private sortSelectedFirst(list: SatOrbitalData[]): SatOrbitalData[] {
    const selected: SatOrbitalData[] = [];
    const others: SatOrbitalData[] = [];
    for (let i = 0; i < list.length; i++) {
      const s = list[i];
      if (this.selectedCats.indexOf(s.catnum) >= 0) {
        selected.push(s);
      } else {
        others.push(s);
      }
    }
    this.sortAlphabetical(selected);
    this.sortAlphabetical(others);
    return selected.concat(others);
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
      this.refreshList();
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

  private refreshList(): void {
    const all = this.app.getStore().getAll();
    this.showingAll = this.sortSelectedFirst(all);
    this.dataSource.setData(this.showingAll);
    this.selectedCount = this.selectedCats.length;
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
      this.refreshList();
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
      this.refreshList();
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

  private applySearchQuery(): void {
    const q = this.searchQuery.trim().toLowerCase();
    const all = this.app.getStore().getAll();
    const list: SatOrbitalData[] = [];
    if (q.length === 0) {
      this.searchResults = [];
      return;
    }
    for (let i = 0; i < all.length; i++) {
      const s = all[i];
      if (s.name.toLowerCase().indexOf(q) >= 0 || String(s.catnum).indexOf(q) >= 0) {
        list.push(s);
        if (list.length >= 50) {
          break;
        }
      }
    }
    this.searchResults = this.sortSelectedFirst(list);
  }

  private datasetColor(item: SatOrbitalData): ResourceColor {
    return item.isDeepSpace ? '#E67E22' : '#0A59F7';
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Row() {
          Text('卫星').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.color_text'))
          Blank()
          Text(`已选 ${this.selectedCount} 颗（置顶）`)
            .fontSize(12)
            .fontColor($r('app.color.color_text_secondary'))
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 6 })

        if (this.showingAll.length === 0) {
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
            LazyForEach(this.dataSource, (item: SatOrbitalData) => {
              ListItem() {
                this.satRow(item)
              }
            }, (item: SatOrbitalData): string => {
              return String(item.catnum)
            })
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ bottom: 16, left: 14, right: 14 })
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

                Text(SelectedSats.isSelected(s.catnum) ? '已选' : '选择')
                  .fontSize(12)
                  .fontColor(SelectedSats.isSelected(s.catnum) ? '#FFFFFF' : $r('app.color.color_primary'))
                  .backgroundColor(SelectedSats.isSelected(s.catnum) ? $r('app.color.color_primary') : $r('app.color.color_card'))
                  .borderRadius(14)
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              }
              .width('100%')
              .padding(8)
              .backgroundColor($r('app.color.color_card'))
              .borderRadius(8)
              .onClick((): void => {
                SelectedSats.toggle(s.catnum)
              })
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
    Column({ space: 12 }) {
      this.floatButton('↑', '返回顶部', 'top')
      this.floatButton('🔍', '搜索', 'search')
    }
    .alignItems(HorizontalAlign.End)
    .margin({ right: 14, bottom: 14 })
  }

  @Builder
  private floatButton(icon: string, labelTxt: string, action: string) {
    Column({ space: 2 }) {
      Button(icon)
        .type(ButtonType.Circle)
        .width(48)
        .height(48)
        .fontSize(20)
        .backgroundColor($r('app.color.color_primary'))
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
  private satRow(item: SatOrbitalData) {
    Row({ space: 12 }) {
      Column() {
        Text(item.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_text'))
          .maxLines(1)
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
            SelectedSats.toggle(item.catnum)
          }
        })

      Row()
        .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(12)
  }

  private isSelectedLocal(catnum: number): boolean {
    return this.selectedCats.indexOf(catnum) >= 0;
  }
}