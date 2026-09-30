import { promptAction } from '@kit.ArkUI';
import { qthToPosition, positionToQth } from '../../domain/qth/QthConverter';
import { AppSettings, WINDOW_PRESETS } from '../../common/AppSettings';
import { Locator } from '../../common/Locator';
import { SatelliteApp } from '../../common/SatelliteApp';
import { SelectedSats } from '../../common/SelectedSats';
import { CN_TLE_URL, SatelliteDownloader } from '../../data/downloader/SatelliteDownloader';
import { ENTER_SCALE, PRESS_IN_MS, PRESS_OUT_MS, PRESS_SCALE } from '../components/PressFx';
import { TAB_BAR_CLEARANCE } from '../../common/LayoutMetrics';

@Component
export struct SettingsPage {
  @State latText: string = '48.2';
  @State lonText: string = '16.37';
  @State altText: string = '0';
  @State qthText: string = '';
  @State customWindowText: string = '';
  @State customSelected: boolean = false;
  @State satCount: number = 0;
  @State transCount: number = 0;
  @State minElevation: number = 5;
  @State pressedBtn: string = '';
  @State btnEntered: boolean = false;
  @State tleUrlText: string = '';
  @State transUrlText: string = '';
  @State updating: boolean = false;
  /** 预测窗口数值切换动画进度 0→1 */
  @State winFx: number = 1;
  @StorageLink('settings_window_hours') windowHours: number = 24;
  @StorageProp('station_version') @Watch('onStationChanged') stationVersion: number = 0;
  private wasLoaded: boolean = false;
  private app: SatelliteApp = SatelliteApp.getInstance();

  aboutToAppear(): void {
    if (this.wasLoaded) {
      return;
    }
    this.wasLoaded = true;
    const station = AppSettings.getStation();
    this.latText = station.latitude.toFixed(4);
    this.lonText = station.longitude.toFixed(4);
    this.altText = station.altitude.toFixed(0);
    this.qthText = positionToQth(station.latitude, station.longitude) ?? '';
    this.minElevation = AppSettings.getMinElevation();
    this.tleUrlText = AppSettings.getCustomTleUrl();
    this.transUrlText = AppSettings.getCustomTransponderUrl();
    this.refreshCounts();
  }

  /** 站址被静默更新（启动定位）或别处修改后，同步已显示的内容，避免停留过期值。 */
  onStationChanged(): void {
    const station = AppSettings.getStation();
    this.latText = station.latitude.toFixed(4);
    this.lonText = station.longitude.toFixed(4);
    this.altText = station.altitude.toFixed(0);
    this.qthText = positionToQth(station.latitude, station.longitude) ?? this.qthText;
  }

  private refreshCounts(): void {
    this.satCount = this.app.getStore().getAll().length;
    this.transCount = this.app.getStore().getTransponders().length;
  }

  private selCountStr(): string {
    return String(SelectedSats.getCats().length);
  }

  private applyQth(): void {
    if (this.qthText.trim().length === 0) {
      return;
    }
    const pos = qthToPosition(this.qthText);
    if (pos === null) {
      promptAction.showToast({ message: 'QTH 定位器无效' });
      return;
    }
    this.latText = pos.latitude.toFixed(4);
    this.lonText = pos.longitude.toFixed(4);
    this.autoSaveStation();
  }

  /** 把输入框恢复成当前生效的站址。 */
  private revertStationFields(): void {
    const s = AppSettings.getStation();
    this.latText = s.latitude.toFixed(4);
    this.lonText = s.longitude.toFixed(4);
    this.altText = s.altitude.toFixed(0);
  }

  private async locate(): Promise<void> {
    promptAction.showToast({ message: '正在定位…' });
    const pos = await Locator.getCurrentPosition(getContext(this), true);
    if (pos === null) {
      promptAction.showToast({ message: '定位失败，请检查定位权限/开关' });
      return;
    }
    this.latText = pos.latitude.toFixed(4);
    this.lonText = pos.longitude.toFixed(4);
    // 海拔不可信时沿用已保存的值，不要用 0/粗差覆盖
    const alt = Locator.altitudeIsUsable(pos.altitude) ? pos.altitude : AppSettings.getStation().altitude;
    this.altText = alt.toFixed(0);
    AppSettings.setStation(pos.latitude, pos.longitude, alt, true);
    this.qthText = positionToQth(pos.latitude, pos.longitude) ?? '';
    const altHint = Locator.altitudeIsUsable(pos.altitude) ? '' : '（海拔沿用原值）';
    promptAction.showToast({ message: `已定位：${this.qthText}${altHint}` });
  }

  // ---- 自定义数据源 ----

  private currentSourceHint(): string {
    const custom = AppSettings.getCustomTleUrl();
    if (custom.length === 0) {
      return `当前：内置镜像 ${CN_TLE_URL}`;
    }
    return `当前：自定义 ${custom}`;
  }

  private async saveAndUpdateSource(): Promise<void> {
    if (this.updating) {
      return;
    }
    const tle = this.tleUrlText.trim();
    const trans = this.transUrlText.trim();
    if (tle.length > 0 && !SatelliteDownloader.isUsableUrl(tle)) {
      promptAction.showToast({ message: '数据地址需以 http:// 或 https:// 开头' });
      return;
    }
    if (trans.length > 0 && !SatelliteDownloader.isUsableUrl(trans)) {
      promptAction.showToast({ message: '转发器地址需以 http:// 或 https:// 开头' });
      return;
    }
    AppSettings.setCustomTleUrl(tle);
    AppSettings.setCustomTransponderUrl(trans);
    this.updating = true;
    promptAction.showToast({ message: '正在更新…' });
    try {
      const count = await this.app.downloadAndStore();
      try {
        await this.app.downloadTranspondersAndStore();
      } catch (e) {
        // 转发器可选，失败不影响卫星数据
      }
      this.refreshCounts();
      promptAction.showToast({ message: `已更新 ${count} 颗卫星` });
    } catch (e) {
      promptAction.showToast({ message: '更新失败，请检查地址与网络' });
    }
    this.updating = false;
  }

  private resetSource(): void {
    AppSettings.setCustomTleUrl('');
    AppSettings.setCustomTransponderUrl('');
    this.tleUrlText = '';
    this.transUrlText = '';
    promptAction.showToast({ message: '已恢复内置数据源' });
  }

  private validLatLon(lat: number, lon: number): boolean {
    return !Number.isNaN(lat) && !Number.isNaN(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
  }

  /** 输入完成即自动保存；非法则回滚输入框并提示，不写入站址。 */
  private autoSaveStation(): void {
    if (this.latText.trim().length === 0 || this.lonText.trim().length === 0) {
      this.revertStationFields();
      promptAction.showToast({ message: '经纬度不能为空，已还原' });
      return;
    }
    const lat = Number(this.latText);
    const lon = Number(this.lonText);
    const alt = Number(this.altText);
    if (!this.validLatLon(lat, lon)) {
      this.revertStationFields();
      promptAction.showToast({ message: '经纬度无效，已还原为上次保存的值' });
      return;
    }
    AppSettings.setStation(lat, lon, Number.isNaN(alt) ? 0 : alt, true);
    const qth = positionToQth(lat, lon);
    if (qth !== null) {
      this.qthText = qth;
    }
    promptAction.showToast({ message: '站址已保存' });
  }

  /** 已生效（AppStorage 里）的站址，用于给自动保存直观反馈。 */
  private savedStationText(): string {
    const s = AppSettings.getStation();
    const qth = AppStorage.get<string>('station_qth') ?? '';
    const suffix = qth.length > 0 ? `  ${qth}` : '';
    return `${s.latitude.toFixed(4)}, ${s.longitude.toFixed(4)}, ${s.altitude.toFixed(0)}m${suffix}`;
  }

  private onMinElevationChange(v: number, mode: SliderChangeMode): void {
    this.minElevation = Math.round(v);
    if (mode === SliderChangeMode.End) {
      AppSettings.setMinElevation(this.minElevation);
    }
  }

  private onWindowChange(v: number): void {
    this.windowHours = v;
  }

  // ---- 按钮动画 ----

  /**
   * 预测窗口切换动画：与卫星页选择动画同一套（320ms + Friction）。
   * 先瞬回 0（duration=0 不产生动画），下一帧再动画到 1。
   */
  private playWinFx(): void {
    this.getUIContext().animateTo({ duration: 0, curve: Curve.Linear }, (): void => {
      this.winFx = 0;
    });
    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: 320, curve: Curve.Friction }, (): void => {
        this.winFx = 1;
      });
    }, 0);
  }

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

  build() {
    Column({ space: 14 }) {
      Row() {
        Text('设置').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.color_text'))
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 6 })

      Scroll() {
        Column({ space: 14 }) {
          this.sectionData()
          this.sectionForecast()
          this.sectionStation()
          this.sectionCustomSource()
          this.currentSummary()
          this.sectionAbout()
        }
        .width('100%')
        // 底部预留悬浮胶囊栏空间，保证最后一个卡片能滚到胶囊上方
        .padding({ left: 16, right: 16, bottom: TAB_BAR_CLEARANCE })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_bg'))
    .onAppear((): void => {
      this.getUIContext().animateTo({ duration: PRESS_OUT_MS, curve: Curve.Friction }, (): void => {
        this.btnEntered = true;
      });
    })
  }

  @Builder
  private sectionData() {
    Column({ space: 8 }) {
      Row() {
        Text('数据状态').fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.color_text'))
      }
      .width('100%')

      Grid() {
        GridItem() {
          this.dataBox('卫星', `${this.satCount}`)
        }
        GridItem() {
          this.dataBox('转发器', `${this.transCount}`)
        }
        GridItem() {
          this.dataBox('跟踪中', this.selCountStr())
        }
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(8)
      .rowsGap(8)
      .width('100%')

      Button('刷新数据')
        .width('100%')
        .fontSize(14)
        .scale({ x: this.pressScale('set-refresh'), y: this.pressScale('set-refresh') })
        .onTouch((event: TouchEvent): void => {
          this.onBtnTouch('set-refresh', event);
        })
        .onClick((): void => {
          this.reloadData()
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private sectionCustomSource() {
    Column({ space: 10 }) {
      Row() {
        Text('自定义数据源').fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.color_text'))
        Blank()
        if (this.updating) {
          LoadingProgress()
            .width(14)
            .height(14)
            .color($r('app.color.color_primary'))
        }
      }
      .width('100%')

      Text(this.currentSourceHint())
        .fontSize(11)
        .fontColor($r('app.color.color_text_secondary'))
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      TextInput({ placeholder: '卫星', text: this.tleUrlText })
        .width('100%')
        .height(38)
        .fontSize(12)
        .type(InputType.Normal)
        .onChange((v: string): void => {
          this.tleUrlText = v
        })

      TextInput({ placeholder: '接收器', text: this.transUrlText })
        .width('100%')
        .height(38)
        .fontSize(12)
        .type(InputType.Normal)
        .onChange((v: string): void => {
          this.transUrlText = v
        })

      Row({ space: 8 }) {
        Button(this.updating ? '更新中…' : '保存并更新')
          .layoutWeight(1)
          .fontSize(14)
          .backgroundColor($r('app.color.color_primary'))
          .enabled(!this.updating)
          .opacity(this.updating ? 0.6 : 1)
          .scale({ x: this.pressScale('set-src-save'), y: this.pressScale('set-src-save') })
          .onTouch((event: TouchEvent): void => {
            this.onBtnTouch('set-src-save', event);
          })
          .onClick((): void => {
            this.saveAndUpdateSource()
          })
        Button('恢复默认')
          .fontSize(14)
          .enabled(!this.updating)
          .opacity(this.updating ? 0.6 : 1)
          .scale({ x: this.pressScale('set-src-reset'), y: this.pressScale('set-src-reset') })
          .onTouch((event: TouchEvent): void => {
            this.onBtnTouch('set-src-reset', event);
          })
          .onClick((): void => {
            this.resetSource()
          })
      }
      .width('100%')

      Text('支持 TLE 三行文本或 Celestrak CSV；自定义源优先，失败自动回退内置镜像。')
        .fontSize(11)
        .fontColor($r('app.color.color_text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private dataBox(label: string, valueTxt: string) {
    Column({ space: 3 }) {
      Text(valueTxt).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.color_primary'))
      Text(label).fontSize(11).fontColor($r('app.color.color_text_secondary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(10)
    .backgroundColor($r('app.color.color_bg'))
    .borderRadius(8)
  }

  private async reloadData(): Promise<void> {
    promptAction.showToast({ message: '正在更新…' });
    try {
      const count = await this.app.downloadAndStore();
      try {
        await this.app.downloadTranspondersAndStore();
      } catch (e) {
        // optional
      }
      this.refreshCounts();
      promptAction.showToast({ message: `已更新 ${count} 颗卫星` });
    } catch (e) {
      promptAction.showToast({ message: '更新失败' });
    }
  }

  @Builder
  private sectionStation() {
    Column({ space: 10 }) {
      Row() {
        Text('观测站位置').fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.color_text'))
        Blank()
        Text(this.liveQth())
          .fontSize(12)
          .fontColor($r('app.color.color_primary'))
      }
      .width('100%')

      Row({ space: 10 }) {
        Text('纬度').fontSize(14).fontColor($r('app.color.color_text_secondary'))
        TextInput({ placeholder: '纬度', text: this.latText })
          .layoutWeight(1)
          .type(InputType.NUMBER_DECIMAL)
          .onChange((v: string): void => {
            this.latText = v
          })
          .onEditChange((isEditing: boolean): void => {
            if (!isEditing) {
              this.autoSaveStation()
            }
          })
      }
      Row({ space: 10 }) {
        Text('经度').fontSize(14).fontColor($r('app.color.color_text_secondary'))
        TextInput({ placeholder: '经度', text: this.lonText })
          .layoutWeight(1)
          .type(InputType.NUMBER_DECIMAL)
          .onChange((v: string): void => {
            this.lonText = v
          })
          .onEditChange((isEditing: boolean): void => {
            if (!isEditing) {
              this.autoSaveStation()
            }
          })
      }
      Row({ space: 10 }) {
        Text('海拔(m)').fontSize(14).fontColor($r('app.color.color_text_secondary'))
        TextInput({ placeholder: '海拔', text: this.altText })
          .layoutWeight(1)
          .type(InputType.NUMBER_DECIMAL)
          .onChange((v: string): void => {
            this.altText = v
          })
          .onEditChange((isEditing: boolean): void => {
            if (!isEditing) {
              this.autoSaveStation()
            }
          })
      }

      Divider().color($r('app.color.color_divider'))

      Text('QTH 定位器').fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.color_text'))
      Row({ space: 8 }) {
        TextInput({ placeholder: '如 JN88XA', text: this.qthText })
          .layoutWeight(1)
          .onChange((v: string): void => {
            this.qthText = v
          })
          .onEditChange((isEditing: boolean): void => {
            if (!isEditing) {
              this.applyQth()
            }
          })
        Button('填充坐标')
          .fontSize(13)
          .scale({ x: this.pressScale('set-qth'), y: this.pressScale('set-qth') })
          .onTouch((event: TouchEvent): void => {
            this.onBtnTouch('set-qth', event);
          })
          .onClick((): void => {
            this.applyQth()
          })
      }
      .width('100%')

      Button('📌 定位到当前位置')
        .width('100%')
        .fontSize(14)
        .backgroundColor($r('app.color.color_primary'))
        .scale({ x: this.pressScale('set-locate'), y: this.pressScale('set-locate') })
        .onTouch((event: TouchEvent): void => {
          this.onBtnTouch('set-locate', event);
        })
        .onClick((): void => {
          this.locate()
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private sectionForecast() {
    Column({ space: 10 }) {
      Text('过境预报').fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.color_text'))
      Row() {
        Text('最低过境仰角').fontSize(14).fontColor($r('app.color.color_text'))
        Blank()
        Text(`${this.minElevation}°`).fontSize(14).fontColor($r('app.color.color_primary'))
      }
      .width('100%')
      Slider({
        value: this.minElevation,
        min: 0,
        max: 40,
        step: 1,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .onChange((value: number, mode: SliderChangeMode): void => {
          this.onMinElevationChange(value, mode)
        })

      Divider().color($r('app.color.color_divider'))

      Row() {
        Text('预测窗口').fontSize(14).fontColor($r('app.color.color_text'))
        Blank()
        Text(`${this.windowHours} h`)
          .fontSize(14)
          .fontColor($r('app.color.color_primary'))
          // 数值随切换动画一起淡入并轻微上浮
          .opacity(0.15 + 0.85 * this.winFx)
          .translate({ y: 6 * (1 - this.winFx) })
      }
      .width('100%')

      Row({ space: 6 }) {
        ForEach(WINDOW_PRESETS, (h: number) => {
          Text(`${h}h`)
            .fontSize(13)
            .fontColor((!this.customSelected && this.windowHours === h) ? '#FFFFFF' : $r('app.color.color_text_secondary'))
            .backgroundColor((!this.customSelected && this.windowHours === h) ? $r('app.color.color_primary') : $r('app.color.color_bg'))
            .borderRadius(16)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .onClick((): void => {
              // 胶囊着色过渡 + 数值淡入都在同一动画内
              this.getUIContext().animateTo({ duration: 320, curve: Curve.Friction }, (): void => {
                this.customSelected = false
                this.windowHours = h
              });
              this.playWinFx()
            })
        }, (h: number): string => {
          return String(h)
        })
        Text('自定义')
          .fontSize(13)
          .fontColor(this.customSelected ? '#FFFFFF' : $r('app.color.color_text_secondary'))
          .backgroundColor(this.customSelected ? $r('app.color.color_primary') : $r('app.color.color_bg'))
          .borderRadius(16)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .onClick((): void => {
            // 自定义行随展开/收合做转场
            this.getUIContext().animateTo({ duration: 320, curve: Curve.Friction }, (): void => {
              this.customSelected = true
            });
            if (this.customWindowText.length === 0) {
              this.customWindowText = String(this.windowHours)
            }
          })
      }
      .width('100%')

      if (this.customSelected) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '小时 (h)', text: this.customWindowText })
            .layoutWeight(1)
            .type(InputType.Number)
            .height(36)
            .borderRadius(8)
            .onChange((v: string): void => {
              this.customWindowText = v
            })
          Button('应用')
            .fontSize(13)
            .scale({ x: this.pressScale('set-window'), y: this.pressScale('set-window') })
            .onTouch((event: TouchEvent): void => {
              this.onBtnTouch('set-window', event);
            })
            .onClick((): void => {
              this.applyCustomWindow()
            })
        }
        .width('100%')
        // 展开/收合：淡入 + 自上方轻微展开
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })))
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  private isCustomWindow(): boolean {
    return this.customSelected;
  }

  private applyCustomWindow(): void {
    const v = Number(this.customWindowText);
    if (Number.isNaN(v) || v <= 0 || v > 720) {
      promptAction.showToast({ message: '请输入 1-720 之间的小时数' });
      return;
    }
    this.getUIContext().animateTo({ duration: 320, curve: Curve.Friction }, (): void => {
      this.customSelected = false;
      this.windowHours = Math.round(v);
    });
    this.playWinFx();
  }

  @Builder
  private currentSummary() {
    Column({ space: 8 }) {
      Text(`当前生效：${this.savedStationText()}`)
        .fontSize(11)
        .fontColor($r('app.color.color_text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
      Text(`仰角 ≥${AppSettings.getMinElevation()}° · 窗口 ${AppSettings.getWindowHours()}h`)
        .fontSize(11)
        .fontColor($r('app.color.color_text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
  }

  @Builder
  private sectionAbout() {
    Text('业余卫星跟踪/过境预报，算法源自 Look4Sat（GPL-3.0）')
      .fontSize(11)
      .fontColor($r('app.color.color_text_secondary'))
      .width('100%')
      .textAlign(TextAlign.Center)
      .padding({ top: 4 })
  }

  private liveQth(): string {
    const lat = Number(this.latText);
    const lon = Number(this.lonText);
    if (Number.isNaN(lat) || Number.isNaN(lon) || lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      return '坐标无效';
    }
    return positionToQth(lat, lon) ?? '无法定位';
  }
}