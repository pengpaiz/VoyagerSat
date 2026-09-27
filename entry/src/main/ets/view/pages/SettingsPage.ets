import { promptAction } from '@kit.ArkUI';
import { qthToPosition, positionToQth } from '../../domain/qth/QthConverter';
import { AppSettings, WINDOW_PRESETS } from '../../common/AppSettings';
import { Locator } from '../../common/Locator';
import { SatelliteApp } from '../../common/SatelliteApp';
import { SelectedSats } from '../../common/SelectedSats';

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
  @StorageLink('settings_min_elevation') minElevation: number = 5;
  @StorageLink('settings_window_hours') windowHours: number = 24;
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
    this.refreshCounts();
  }

  private refreshCounts(): void {
    this.satCount = this.app.getStore().getAll().length;
    this.transCount = this.app.getStore().getTransponders().length;
  }

  private selCountStr(): string {
    return String(SelectedSats.getCats().length);
  }

  private applyQth(): void {
    const pos = qthToPosition(this.qthText);
    if (pos !== null) {
      this.latText = pos.latitude.toFixed(4);
      this.lonText = pos.longitude.toFixed(4);
    } else {
      promptAction.showToast({ message: 'QTH 定位器无效' });
    }
  }

  private async locate(): Promise<void> {
    promptAction.showToast({ message: '正在定位…' });
    const pos = await Locator.getCurrentPosition(getContext(this));
    if (pos === null) {
      promptAction.showToast({ message: '定位失败，请检查定位权限/开关' });
      return;
    }
    this.latText = pos.latitude.toFixed(4);
    this.lonText = pos.longitude.toFixed(4);
    this.altText = pos.altitude.toFixed(0);
    AppSettings.setStation(pos.latitude, pos.longitude, pos.altitude);
    this.qthText = positionToQth(pos.latitude, pos.longitude) ?? '';
    promptAction.showToast({ message: `已定位：${this.qthText}` });
  }

  private save(): void {
    const lat = Number(this.latText);
    const lon = Number(this.lonText);
    const alt = Number(this.altText);
    if (Number.isNaN(lat) || Number.isNaN(lon) || lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      promptAction.showToast({ message: '经纬度无效' });
      return;
    }
    AppSettings.setStation(lat, lon, Number.isNaN(alt) ? 0 : alt);
    const qth = positionToQth(lat, lon);
    if (qth !== null) {
      this.qthText = qth;
    }
    promptAction.showToast({ message: '站址已保存' });
  }

  private onMinElevationChange(v: number): void {
    this.minElevation = Math.round(v);
  }

  private onWindowChange(v: number): void {
    this.windowHours = v;
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
          this.sectionStation()
          this.sectionForecast()
          this.currentSummary()
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_bg'))
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
      }
      Row({ space: 10 }) {
        Text('经度').fontSize(14).fontColor($r('app.color.color_text_secondary'))
        TextInput({ placeholder: '经度', text: this.lonText })
          .layoutWeight(1)
          .type(InputType.NUMBER_DECIMAL)
          .onChange((v: string): void => {
            this.lonText = v
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
      }

      Divider().color($r('app.color.color_divider'))

      Text('QTH 定位器').fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.color_text'))
      Row({ space: 8 }) {
        TextInput({ placeholder: '如 JN88XA', text: this.qthText })
          .layoutWeight(1)
          .onChange((v: string): void => {
            this.qthText = v
          })
        Button('填充坐标')
          .fontSize(13)
          .onClick((): void => {
            this.applyQth()
          })
      }
      .width('100%')

      Button('📌 定位到当前位置')
        .width('100%')
        .fontSize(14)
        .backgroundColor($r('app.color.color_primary'))
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
        .onChange((value: number): void => {
          this.onMinElevationChange(value)
        })

      Divider().color($r('app.color.color_divider'))

      Row() {
        Text('预测窗口').fontSize(14).fontColor($r('app.color.color_text'))
        Blank()
        Text(`${this.windowHours} h`).fontSize(14).fontColor($r('app.color.color_primary'))
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
              this.customSelected = false
              this.windowHours = h
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
            this.customSelected = true
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
            .onClick((): void => {
              this.applyCustomWindow()
            })
        }
        .width('100%')
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
    this.customSelected = false;
    this.windowHours = Math.round(v);
  }

  @Builder
  private currentSummary() {
    Column({ space: 8 }) {
      Button('保存站址')
        .width('100%')
        .backgroundColor($r('app.color.color_primary'))
        .onClick((): void => {
          this.save()
        })
      Text(`当前观测量：${this.qthLabel()}  最低仰角 ${AppSettings.getMinElevation()}°  窗口 ${AppSettings.getWindowHours()}h`)
        .fontSize(11)
        .fontColor($r('app.color.color_text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
  }

  private qthLabel(): string {
    return this.qthText.length > 0 ? this.qthText : '--';
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