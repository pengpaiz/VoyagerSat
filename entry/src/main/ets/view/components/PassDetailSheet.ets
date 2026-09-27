import { SatelliteApp } from '../../common/SatelliteApp';
import { AppSettings } from '../../common/AppSettings';
import { SatPassEvent } from '../../domain/predict/SatPassFinder';
import { createOrbitalObject } from '../../domain/predict/OrbitalFactory';
import { SatOrbitalPos } from '../../domain/predict/OrbitalPos';
import { RadarCanvas } from './RadarCanvas';
import { SatRadio } from '../../domain/model/SatRadio';
import { buildPassTrack, RadarTrackResult, FreqInfo } from '../../domain/predict/RadarTrack';
import { SatCelestialComputer } from '../../domain/predict/CelestialComputer';
import { sensor } from '@kit.SensorServiceKit';
import { DeviceOrientation } from '../../common/DeviceOrientation';
import { toDegrees } from '../../common/utils/MathUtils';

function degRad(rad: number): number {
  return toDegrees(rad);
}

function fmtMhz(hz: number): string {
  return `${(hz / 1000000).toFixed(3)} MHz`;
}

export class PassDetailPayload {
  catnum: number = 0;
  name: string = '';
  color: string = '#0A59F7';
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
  downlinks: FreqInfo[] = [];
  uplinks: FreqInfo[] = [];
  hasTransponders: boolean = false;
}

@Component
export struct PassDetailSheet {
  @Prop detail: PassDetailPayload = new PassDetailPayload();

  @State aimAzDeg: number = 0;
  @State aimTiltDeg: number = 0;
  private orientation: DeviceOrientation = new DeviceOrientation();
  private declinationDeg: number = 0;

  aboutToAppear(): void {
    this.startHeadingSensor();
  }

  aboutToDisappear(): void {
    this.stopHeadingSensor();
  }

  static buildPayload(catnum: number, pass: SatPassEvent, color: string): PassDetailPayload {
    const app = SatelliteApp.getInstance();
    const store = app.getStore();
    const payload = new PassDetailPayload();
    payload.catnum = catnum;
    payload.color = color === '' ? '#0A59F7' : color;
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

    // 转发器（多普勒校正频率）
    const radios = store.getTranspondersFor(catnum);
    payload.hasTransponders = radios.length > 0;
    const dls: FreqInfo[] = [];
    const uls: FreqInfo[] = [];
    for (let i = 0; i < radios.length; i++) {
      PassDetailSheet.collectFreqs(radios[i], pos, dls, uls);
    }
    payload.downlinks = dls;
    payload.uplinks = uls;
    return payload;
  }

  private static collectFreqs(t: SatRadio, pos: SatOrbitalPos, dls: FreqInfo[], uls: FreqInfo[]): void {
    if (t.downlinkLow !== null) {
      dls.push(new FreqInfo(t.downlinkMode ?? 'DL',
        fmtMhz(pos.getDownlinkFreq(t.downlinkLow))));
    }
    if (t.uplinkLow !== null) {
      uls.push(new FreqInfo(t.uplinkMode ?? 'UL',
        fmtMhz(pos.getUplinkFreq(t.uplinkLow))));
    }
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
    Column({ space: 14 }) {
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
        headingTiltDeg: this.aimTiltDeg
      })
        .width('100%')

      this.statsGrid()

      this.downlinkCard()
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
  private downlinkCard() {
    Column({ space: 6 }) {
      Text('收发频率（多普勒校正）')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.color_text'))
      if (!this.detail.hasTransponders) {
        Text('暂无转发器数据（可从“国内数据下载”获取）')
          .fontSize(12)
          .fontColor($r('app.color.color_text_secondary'))
      } else {
        if (this.detail.downlinks.length > 0) {
          Row({ space: 8 }) {
            Text('下行').fontSize(12).fontColor($r('app.color.color_text_secondary'))
            Blank()
            this.freqChips(this.detail.downlinks)
          }
          .width('100%')
        }
        if (this.detail.uplinks.length > 0) {
          Row({ space: 8 }) {
            Text('上行').fontSize(12).fontColor($r('app.color.color_text_secondary'))
            Blank()
            this.freqChips(this.detail.uplinks)
          }
          .width('100%')
        }
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(10)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private freqChips(list: FreqInfo[]) {
    Column({ space: 4 }) {
      ForEach(list, (f: FreqInfo) => {
        Text(`${f.mode} ${f.display}`)
          .fontSize(12)
          .fontColor($r('app.color.color_text'))
      }, (f: FreqInfo): string => {
        return f.mode + f.display
      })
    }
    .alignItems(HorizontalAlign.End)
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