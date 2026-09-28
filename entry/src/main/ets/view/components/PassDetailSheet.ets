import { SatelliteApp } from '../../common/SatelliteApp';
import { AppSettings } from '../../common/AppSettings';
import { SatPassEvent } from '../../domain/predict/SatPassFinder';
import { createOrbitalObject } from '../../domain/predict/OrbitalFactory';
import { SatOrbitalPos } from '../../domain/predict/OrbitalPos';
import { SatOrbitalObject } from '../../domain/predict/OrbitalObject';
import { SatGeoPos } from '../../domain/predict/GeoPos';
import { RadarCanvas } from './RadarCanvas';
import { SatRadio } from '../../domain/model/SatRadio';
import { buildPassTrack, RadarTrackResult } from '../../domain/predict/RadarTrack';
import { SatCelestialComputer } from '../../domain/predict/CelestialComputer';
import { sensor } from '@kit.SensorServiceKit';
import { DeviceOrientation } from '../../common/DeviceOrientation';
import { toDegrees } from '../../common/utils/MathUtils';

const DOPPLER_REFRESH_MS = 5000;
const LIVE_REFRESH_MS = 1000;
const NO_LINK_TEXT = '- - . - -';

function degRad(rad: number): number {
  return toDegrees(rad);
}

function fmtMhz(hz: number): string {
  return `${(hz / 1000000).toFixed(4)} MHz`;
}

function fmtRange(lowHz: number, highHz: number): string {
  if (highHz <= 0 || highHz === lowHz) {
    return fmtMhz(lowHz);
  }
  return `${fmtMhz(lowHz)} - ${fmtMhz(highHz)}`;
}

function fmtOrNoLink(hasValue: boolean, lowHz: number, highHz: number): string {
  if (!hasValue || lowHz <= 0) {
    return NO_LINK_TEXT;
  }
  return fmtRange(lowHz, highHz);
}

export class FreqRowView {
  dir: string = '';
  hasValue: boolean = false;
  rawLowHz: number = -1;
  rawHighHz: number = -1;
  isDownlink: boolean = true;
  rawText: string = '';
  dopText: string = '';

  constructor(dir: string, hasValue: boolean, rawLowHz: number, rawHighHz: number, isDownlink: boolean,
              rawText: string, dopText: string) {
    this.dir = dir;
    this.hasValue = hasValue;
    this.rawLowHz = rawLowHz;
    this.rawHighHz = rawHighHz;
    this.isDownlink = isDownlink;
    this.rawText = rawText;
    this.dopText = dopText;
  }
}

/** 一个转发器：固定 RX(下行)/TX(上行) 两行。 */
export class FreqTxView {
  title: string = '';
  rows: FreqRowView[] = [];

  constructor(title: string, rows: FreqRowView[]) {
    this.title = title;
    this.rows = rows;
  }
}

export class FreqGroupView {
  mode: string = '';
  blocks: FreqTxView[] = [];

  constructor(mode: string, blocks: FreqTxView[]) {
    this.mode = mode;
    this.blocks = blocks;
  }
}

class FreqEntry {
  mode: string = '';
  title: string = '';
  downlow: number = -1;
  downhigh: number = -1;
  upLow: number = -1;
  upHigh: number = -1;
  downIsSet: boolean = false;
  upIsSet: boolean = false;

  constructor(mode: string, title: string, downlow: number, downhigh: number, upLow: number, upHigh: number,
              downIsSet: boolean, upIsSet: boolean) {
    this.mode = mode;
    this.title = title;
    this.downlow = downlow;
    this.downhigh = downhigh;
    this.upLow = upLow;
    this.upHigh = upHigh;
    this.downIsSet = downIsSet;
    this.upIsSet = upIsSet;
  }
}

export class PassDetailPayload {
  catnum: number = 0;
  name: string = '';
  color: string = '#E67E22';
  aosTime: number = 0;
  losTime: number = 0;
  maxElevationDeg: number = 0;
  durationMillis: number = 0;
  tcaPos: SatOrbitalPos = new SatOrbitalPos();
  eclipsed: boolean = false;
  sunAzDeg: number = -999;
  sunElevDeg: number = -999;
  moonAzDeg: number = -999;
  moonElevDeg: number = -999;
  track: RadarTrackResult = new RadarTrackResult([], [], []);
  freqGroups: FreqGroupView[] = [];
  hasTransponders: boolean = false;
}

@Component
export struct PassDetailSheet {
  @Prop @Watch('onFreqSourceChanged') detail: PassDetailPayload = new PassDetailPayload();
  @State freqView: FreqGroupView[] = [];

  @State aimAzDeg: number = 0;
  @State aimTiltDeg: number = 0;
  @State liveAzDeg: number = -999;
  @State liveElevDeg: number = -999;
  @State liveInPass: boolean = false;
  @State liveProgress: number = 0;
  private orientation: DeviceOrientation = new DeviceOrientation();
  private declinationDeg: number = 0;
  private orbital: SatOrbitalObject | null = null;
  private station: SatGeoPos = new SatGeoPos(0, 0);
  private freqTimerId: number = -1;
  private liveTimerId: number = -1;

  aboutToAppear(): void {
    this.startHeadingSensor();
    this.buildOrbital();
    this.refreshFreqView();
    this.updateLivePosition();
    this.freqTimerId = setInterval((): void => {
      this.refreshFreqView();
    }, DOPPLER_REFRESH_MS);
    this.liveTimerId = setInterval((): void => {
      this.updateLivePosition();
    }, LIVE_REFRESH_MS);
  }

  aboutToDisappear(): void {
    this.stopHeadingSensor();
    if (this.freqTimerId >= 0) {
      clearInterval(this.freqTimerId);
      this.freqTimerId = -1;
    }
    if (this.liveTimerId >= 0) {
      clearInterval(this.liveTimerId);
      this.liveTimerId = -1;
    }
  }

  onFreqSourceChanged(): void {
    this.buildOrbital();
    this.refreshFreqView();
  }

  /** 每秒更新：正在过境时计算实时位置（黄色圆点）与过境进度。 */
  private updateLivePosition(): void {
    const now = Date.now();
    const inPass = now >= this.detail.aosTime && now <= this.detail.losTime;
    this.liveInPass = inPass;
    if (!inPass) {
      this.liveAzDeg = -999;
      this.liveElevDeg = -999;
      this.liveProgress = 0;
      return;
    }
    const dur = Math.max(1, this.detail.losTime - this.detail.aosTime);
    this.liveProgress = Math.max(0, Math.min(1, (now - this.detail.aosTime) / dur));
    if (this.orbital !== null) {
      const pos = this.orbital.getFullPosition(this.station, now);
      this.liveAzDeg = degRad(pos.azimuth);
      this.liveElevDeg = degRad(pos.elevation);
    }
  }

  static buildPayload(catnum: number, pass: SatPassEvent, color: string): PassDetailPayload {
    const app = SatelliteApp.getInstance();
    const store = app.getStore();
    const payload = new PassDetailPayload();
    payload.catnum = catnum;
    payload.color = color === '' ? '#E67E22' : color;
    payload.aosTime = pass.aosTime;
    payload.losTime = pass.losTime;
    payload.maxElevationDeg = pass.maxElevationDeg;
    payload.durationMillis = pass.durationMillis;
    const satData = store.getByCatnum(catnum);
    if (satData === null) {
      payload.name = `NORAD ${catnum}`;
      return payload;
    }
    payload.name = satData.name;
    const station = AppSettings.getStation();
    const obj = createOrbitalObject(satData);
    // TCA 时刻取 AOS/LOS 中点
    const tca = Math.floor((pass.aosTime + pass.losTime) / 2);
    const pos = obj.getFullPosition(station, tca);
    payload.tcaPos = pos;
    payload.eclipsed = pos.eclipsed;
    const sun = SatCelestialComputer.getSunPosition(station, tca);
    payload.sunAzDeg = degRad(sun.azimuth);
    payload.sunElevDeg = degRad(sun.elevation);
    const moon = SatCelestialComputer.getMoonPosition(station, tca);
    payload.moonAzDeg = degRad(moon.azimuth);
    payload.moonElevDeg = degRad(moon.elevation);
    payload.track = buildPassTrack(obj, station, pass, 1, 60);

    // 转发器（按模式分组，原始频率）
    const radios = store.getTranspondersFor(catnum);
    payload.hasTransponders = radios.length > 0;
    payload.freqGroups = PassDetailSheet.buildFreqGroups(radios);
    return payload;
  }

  private static buildFreqGroups(radios: SatRadio[]): FreqGroupView[] {
    const entries: FreqEntry[] = [];
    for (let i = 0; i < radios.length; i++) {
      const t = radios[i];
      const title = PassDetailSheet.radioTitle(t);
      entries.push(new FreqEntry(
        t.downlinkMode ?? t.uplinkMode ?? 'UNKNOWN',
        title,
        t.downlinkLow === null ? -1 : t.downlinkLow,
        t.downlinkHigh === null ? (t.downlinkLow === null ? -1 : t.downlinkLow) : t.downlinkHigh,
        t.uplinkLow === null ? -1 : t.uplinkLow,
        t.uplinkHigh === null ? (t.uplinkLow === null ? -1 : t.uplinkLow) : t.uplinkHigh,
        t.downlinkLow !== null,
        t.uplinkLow !== null));
    }
    entries.sort((a: FreqEntry, b: FreqEntry): number => a.mode.localeCompare(b.mode));
    const groups: FreqGroupView[] = [];
    for (let i = 0; i < entries.length; i++) {
      const e = entries[i];
      const rows: FreqRowView[] = [];
      const downRaw = fmtOrNoLink(e.downIsSet, e.downlow, e.downhigh);
      const upRaw = fmtOrNoLink(e.upIsSet, e.upLow, e.upHigh);
      rows.push(new FreqRowView('RX 下行', e.downIsSet, e.downlow, e.downhigh, true, downRaw, downRaw));
      rows.push(new FreqRowView('TX 上行', e.upIsSet, e.upLow, e.upHigh, false, upRaw, upRaw));
      const block = new FreqTxView(e.title, rows);
      let group: FreqGroupView | null = null;
      for (let g = 0; g < groups.length; g++) {
        if (groups[g].mode === e.mode) {
          group = groups[g];
          break;
        }
      }
      if (group === null) {
        group = new FreqGroupView(e.mode, []);
        groups.push(group);
      }
      group.blocks.push(block);
    }
    return groups;
  }

  private static radioTitle(t: SatRadio): string {
    const inv = t.isInverted ? 'INV: ' : '';
    const base = t.info.length > 0 ? t.info : 'Transceiver';
    const mode = `${t.downlinkMode ?? '-'}/${t.uplinkMode ?? '-'}`;
    return `${inv}${base} (${mode})`;
  }

  private buildOrbital(): void {
    const app = SatelliteApp.getInstance();
    const sat = app.getStore().getByCatnum(this.detail.catnum);
    if (sat !== null) {
      this.orbital = createOrbitalObject(sat);
    } else {
      this.orbital = null;
    }
    this.station = AppSettings.getStation();
  }

  private refreshFreqView(): void {
    const src = this.detail.freqGroups;
    const views: FreqGroupView[] = [];
    const now = Date.now();
    for (let i = 0; i < src.length; i++) {
      const blocks: FreqTxView[] = [];
      for (let j = 0; j < src[i].blocks.length; j++) {
        const b = src[i].blocks[j];
        const rows: FreqRowView[] = [];
        for (let k = 0; k < b.rows.length; k++) {
          const r = b.rows[k];
          let dopText = r.rawText;
          if (r.hasValue && this.orbital !== null) {
            const pos = this.orbital.getFullPosition(this.station, now);
            const low = r.isDownlink ? pos.getDownlinkFreq(r.rawLowHz) : pos.getUplinkFreq(r.rawLowHz);
            const high = r.isDownlink ? pos.getDownlinkFreq(r.rawHighHz) : pos.getUplinkFreq(r.rawHighHz);
            dopText = fmtRange(low, high);
          }
          rows.push(new FreqRowView(r.dir, r.hasValue, r.rawLowHz, r.rawHighHz, r.isDownlink, r.rawText, dopText));
        }
        blocks.push(new FreqTxView(b.title, rows));
      }
      views.push(new FreqGroupView(src[i].mode, blocks));
    }
    this.freqView = views;
  }

  private startHeadingSensor(): void {
    this.orientation.start((azimuth: number, pitch: number): void => {
      this.aimAzDeg = (azimuth + this.declinationDeg + 360) % 360;
      this.aimTiltDeg = pitch;
    });
    this.fetchDeclination();
  }

  private stopHeadingSensor(): void {
    this.orientation.stop();
  }

  private fetchDeclination(): void {
    const station = AppSettings.getStation();
    const loc: sensor.LocationOptions = {
      latitude: station.latitude,
      longitude: station.longitude,
      altitude: station.altitude
    };
    sensor.getGeomagneticInfo(loc, Date.now()).then((resp: sensor.GeomagneticResponse): void => {
      this.declinationDeg = resp.deflectionAngle;
    }).catch(() => {
    });
  }

  private clock(millis: number): string {
    const d = new Date(millis);
    const hh = d.getHours().toString().padStart(2, '0');
    const mm = d.getMinutes().toString().padStart(2, '0');
    return `${hh}:${mm}`;
  }

  private dateLabel(millis: number): string {
    const d = new Date(millis);
    const today = new Date();
    if (d.getFullYear() === today.getFullYear() && d.getMonth() === today.getMonth() && d.getDate() === today.getDate()) {
      return '今天';
    }
    return `${d.getMonth() + 1}月${d.getDate()}日`;
  }

  build() {
    Column({ space: 18 }) {
      Row({ space: 8 }) {
        Text(this.detail.name)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.color_text'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`NORAD ${this.detail.catnum}`)
          .fontSize(12)
          .fontColor(this.detail.color as ResourceColor)
      }
      .width('100%')

      this.passTimesRow()

      if (this.liveInPass) {
        this.liveProgressBar()
      }

      RadarCanvas({
        azimuthDeg: degRad(this.detail.tcaPos.azimuth),
        elevationDeg: degRad(this.detail.tcaPos.elevation),
        track: this.detail.track,
        trackColor: this.detail.color,
        eclipsed: this.detail.eclipsed,
        sunAzDeg: this.detail.sunAzDeg,
        sunElevDeg: this.detail.sunElevDeg,
        moonAzDeg: this.detail.moonAzDeg,
        moonElevDeg: this.detail.moonElevDeg,
        headingAzDeg: this.aimAzDeg,
        headingTiltDeg: this.aimTiltDeg,
        liveAzDeg: this.liveAzDeg,
        liveElevDeg: this.liveElevDeg
      })
        .width('100%')
        .padding(10)
        .backgroundColor($r('app.color.color_panel_radar'))
        .borderRadius(14)

      Scroll() {
        Column({ space: 14 }) {
          this.statsGrid()

          this.freqCard()
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.color_panel_data'))
        .borderRadius(14)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private statsGrid() {
    Grid() {
      GridItem() {
        this.statBox('方位', `${degRad(this.detail.tcaPos.azimuth).toFixed(0)}°`)
      }
      GridItem() {
        this.statBox('仰角', `${degRad(this.detail.tcaPos.elevation).toFixed(0)}°`)
      }
      GridItem() {
        this.statBox('距离', `${this.detail.tcaPos.distance.toFixed(0)} km`)
      }
      GridItem() {
        this.statBox('高度', `${this.detail.tcaPos.altitude.toFixed(0)} km`)
      }
      GridItem() {
        this.statBox('最高仰角', `${this.detail.maxElevationDeg.toFixed(0)}°`)
      }
      GridItem() {
        this.statBox('时长', `${Math.round(this.detail.durationMillis / 60000)} min`)
      }
    }
    .columnsTemplate('1fr 1fr 1fr')
    .rowsGap(8)
    .columnsGap(8)
    .width('100%')
  }

  @Builder
  private statBox(label: string, value: string) {
    Column({ space: 3 }) {
      Text(label).fontSize(11).fontColor($r('app.color.color_text_secondary'))
      Text(value).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.color_text'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(10)
    .backgroundColor($r('app.color.color_bg'))
    .borderRadius(8)
  }

  @Builder
  private freqCard() {
    Column({ space: 10 }) {
      Row() {
        Text('收发频率')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.color_text'))
        Blank()
        Text('多普勒每 5s 刷新')
          .fontSize(11)
          .fontColor($r('app.color.color_text_secondary'))
      }
      .width('100%')

      if (!this.detail.hasTransponders) {
        Text('暂无转发器数据（可从“国内数据下载”获取）')
          .fontSize(12)
          .fontColor($r('app.color.color_text_secondary'))
      } else {
        Row({ space: 6 }) {
          Text('链路').fontSize(11).fontColor($r('app.color.color_text_secondary')).width(64)
          Text('原始 (MHz)')
            .fontSize(11)
            .fontColor($r('app.color.color_text_secondary'))
            .layoutWeight(1)
            .textAlign(TextAlign.End)
          Text('多普勒 (MHz)')
            .fontSize(11)
            .fontColor($r('app.color.color_text_secondary'))
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
        .width('100%')

        ForEach(this.freqView, (g: FreqGroupView) => {
          Column({ space: 6 }) {
            Text(g.mode)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.color_primary'))
            ForEach(g.blocks, (blk: FreqTxView) => {
              Column({ space: 2 }) {
                Text(blk.title)
                  .fontSize(11)
                  .fontColor($r('app.color.color_text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                ForEach(blk.rows, (r: FreqRowView) => {
                  Row({ space: 6 }) {
                    Text(r.dir).fontSize(12).fontColor($r('app.color.color_text_secondary')).width(64)
                    Text(r.rawText)
                      .fontSize(12)
                      .fontColor(r.hasValue ? $r('app.color.color_text') : $r('app.color.color_text_secondary'))
                      .layoutWeight(1)
                      .textAlign(TextAlign.End)
                    Text(r.dopText)
                      .fontSize(12)
                      .fontColor(r.hasValue ? $r('app.color.color_primary') : $r('app.color.color_text_secondary'))
                      .layoutWeight(1)
                      .textAlign(TextAlign.End)
                  }
                  .width('100%')
                }, (r: FreqRowView): string => r.dir)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }, (blk: FreqTxView, idx: number): string => blk.title + idx)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }, (g: FreqGroupView): string => g.mode)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(10)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private liveProgressBar() {
    Column({ space: 4 }) {
      Row() {
        Text('● 正在过境')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#E6A23C')
        Blank()
        Text(`${Math.round(this.liveProgress * 100)}%`)
          .fontSize(12)
          .fontColor($r('app.color.color_text_secondary'))
      }
      .width('100%')

      Progress({ value: Math.round(this.liveProgress * 100), total: 100, type: ProgressType.Linear })
        .width('100%')
        .color('#E6A23C')
        .backgroundColor('#3D3D3D')
        .height(6)
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(10)
  }

  @Builder
  private passTimesRow() {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text('AOS（捕获）').fontSize(11).fontColor($r('app.color.color_text_secondary'))
        Text(`${this.dateLabel(this.detail.aosTime)} ${this.clock(this.detail.aosTime)}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_text'))
      }
      Blank()
      Column({ space: 2 }) {
        Text('LOS（消失）').fontSize(11).fontColor($r('app.color.color_text_secondary'))
        Text(`${this.dateLabel(this.detail.losTime)} ${this.clock(this.detail.losTime)}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_text'))
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(10)
  }
}