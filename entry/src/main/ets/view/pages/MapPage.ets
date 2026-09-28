/*
 * Look4Sat. World map page (PRC-standard global outline, offline canvas).
 * Night-theme fixed-view map: no pan/zoom. Shows only:
 *  - selected satellite future ground track (one line, until it exits the map)
 *  - footprint (coverage) range circle
 *  - observer station + live satellite positions
 * True-scale local projection: longitude span widens by 1/cos(center latitude),
 * so shapes (footprint, track, landmass) are not distorted at high latitudes.
 */

import { WORLD_RINGS } from '../../domain/map/WorldOutline';
import { SatelliteApp } from '../../common/SatelliteApp';
import { SelectedSats } from '../../common/SelectedSats';
import { AppSettings } from '../../common/AppSettings';
import { SAT_COLORS } from '../../common/SatColors';
import { SatOrbitalData } from '../../domain/predict/OrbitalData';
import { createOrbitalObject } from '../../domain/predict/OrbitalFactory';
import { SatPassEvent, SatPassFinder } from '../../domain/predict/SatPassFinder';
import { SatOrbitalObject } from '../../domain/predict/OrbitalObject';
import { SatOrbitalPos } from '../../domain/predict/OrbitalPos';
import { positionToQth } from '../../domain/qth/QthConverter';
import { toDegrees } from '../../common/utils/MathUtils';
import { RAD2DEG, DEG2RAD } from '../../domain/predict/Constants';
import { hilog } from '@kit.PerformanceAnalysisKit';

const MAP_REFRESH_MS = 1000;
const TRACK_SAMPLE_STEP_MS = 60000;
const TRACK_PERIODS = 2.0;
const MAX_WINDOW_H = 48;
// Viewport window, center follows satellite. Stack aspect ratio is 1.25, so
// BASE_LON_SPAN = VIEW_LAT_SPAN * 1.25 keeps 1° lon == 1° lat in pixels at the equator.
// At high latitudes the effective lon span widens by 1/cos(lat) so shapes keep true scale.
const VIEW_LAT_SPAN = 52.0;
const BASE_LON_SPAN = 65.0;
const MAX_CENTER_LAT = 90.0 - VIEW_LAT_SPAN / 2;
const DEFAULT_CENTER_LON = 105.0;
const DEFAULT_CENTER_LAT = 35.0;
const WATER_COLOR = '#0D1B2A';
const LAND_COLOR = '#16283C';
const BORDER_COLOR = '#33507A';
const GRID_COLOR = '#1F3550';
const STATION_COLOR = '#E53935';
const TRACK_COLOR = '#FF4D4D';
const LIVE_COLOR = '#F5C518';
const FOOTPRINT_COLOR = '#4C8DFF';

class MapSatInfo {
  catnum: number = 0;
  name: string = '';
  color: string = '';
  obj: SatOrbitalObject;
  pass: SatPassEvent | null = null;
  lats: number[] = [];
  lons: number[] = [];
  times: number[] = [];

  constructor(catnum: number, name: string, color: string, obj: SatOrbitalObject) {
    this.catnum = catnum;
    this.name = name;
    this.color = color;
    this.obj = obj;
  }
}

class MapLiveInfo {
  catnum: number;
  name: string;
  color: string;
  az: string;
  el: string;
  dist: string;
  above: boolean;

  constructor(catnum: number, name: string, color: string) {
    this.catnum = catnum;
    this.name = name;
    this.color = color;
    this.az = '--';
    this.el = '--';
    this.dist = '--';
    this.above = false;
  }
}

/** 详情面板数据项：@Prop 保证父组件每次重渲染（每秒）都同步最新数值。 */
@Component
struct MapInfoChip {
  @Prop text: string = '';

  build() {
    Text(this.text)
      .fontSize(12)
      .fontColor($r('app.color.color_text'))
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor($r('app.color.color_bg'))
      .borderRadius(6)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }
}

@Component
export struct MapPage {
  @State sats: MapSatInfo[] = [];
  @State liveList: MapLiveInfo[] = [];
  @State selectedIndex: number = 0;
  @State nowTs: number = Date.now();
  @State viewCenterLon: number = DEFAULT_CENTER_LON;
  @State viewCenterLat: number = DEFAULT_CENTER_LAT;
  @StorageLink('selected_version') @Watch('recompute') selVersion: number = 0;
  @StorageLink('data_version') @Watch('recompute') dataVersion: number = 0;
  @StorageLink('station_latitude') @Watch('recompute') stationLat: number = 48.2;
  @StorageLink('station_longitude') @Watch('recompute') stationLon: number = 16.37;

  private app: SatelliteApp = SatelliteApp.getInstance();
  private finder: SatPassFinder = new SatPassFinder();
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private lastW: number = 0;
  private lastH: number = 0;
  private timerId: number = -1;
  private lastPassRefresh: number = 0;

  aboutToAppear(): void {
    this.recompute();
    this.timerId = setInterval((): void => {
      this.nowTs = Date.now();
      this.refreshSelectedPass(false);
      this.followSelectedSat();
      this.drawNow();
      this.updateLiveList();
    }, MAP_REFRESH_MS);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  recompute(): void {
    const prevCat = this.selectedCatnum();
    const cats = SelectedSats.getCats();
    const store = this.app.getStore();
    const station = AppSettings.getStation();
    const all = store.getAll();
    const now = Date.now();
    const list: MapSatInfo[] = [];
    for (let i = 0; i < cats.length; i++) {
      const satData = this.findSat(all, cats[i]);
      if (satData === null) {
        continue;
      }
      let obj: SatOrbitalObject;
      try {
        obj = createOrbitalObject(satData);
      } catch (e) {
        hilog.warn(0x0001, 'MapPage', `skip bad TLE ${cats[i]}`);
        continue;
      }
      const info = new MapSatInfo(cats[i], satData.name, SAT_COLORS[i % SAT_COLORS.length], obj);
      try {
        const passes = this.finder.getPasses(obj, station, now, MAX_WINDOW_H);
        info.pass = this.nextPass(passes, now);
      } catch (e) {
        hilog.warn(0x0001, 'MapPage', `pass fail ${satData.name}`);
      }
      if (obj.data.meanmo > 1e-8) {
        // Ground track: 2 orbital periods from now
        const lats: number[] = [];
        const lons: number[] = [];
        const times: number[] = [];
        const periodMs = obj.data.orbitalPeriod * 60000;
        const end = now + TRACK_PERIODS * periodMs;
        let t = now;
        let guard = 0;
        while (t <= end && guard < 4000) {
          try {
            const pos = obj.getPosition(station, t);
            lats.push(pos.latitude * RAD2DEG);
            lons.push(this.wrapLon(pos.longitude * RAD2DEG));
            times.push(t);
          } catch (e) {
            // propagation failed for this sample: keep the partial track
          }
          t += TRACK_SAMPLE_STEP_MS;
          guard++;
        }
        info.lats = lats;
        info.lons = lons;
        info.times = times;
      }
      list.push(info);
    }
    this.sats = list;
    // 保持当前选中的卫星（按 NORAD 编号），而不是按列表下标
    this.selectedIndex = this.indexOfCat(prevCat);
    this.lastPassRefresh = Date.now();
    this.followSelectedSat();
    this.updateLiveList();
    this.drawNow();
  }

  private selectedCatnum(): number {
    const info = this.selectedSat();
    return info === null ? -1 : info.catnum;
  }

  private indexOfCat(catnum: number): number {
    if (catnum < 0) {
      return 0;
    }
    for (let i = 0; i < this.sats.length; i++) {
      if (this.sats[i].catnum === catnum) {
        return i;
      }
    }
    return 0;
  }

  /** 当前选中卫星的过境预报到期后自动重算，保证倒计时/下次过境始终有效。 */
  private refreshSelectedPass(force: boolean): void {
    const info = this.selectedSat();
    if (info === null) {
      return;
    }
    const now = this.nowTs;
    const expired = info.pass === null || info.pass.losTime < now;
    if (!force && !expired && now - this.lastPassRefresh < 60000) {
      return;
    }
    this.lastPassRefresh = now;
    const station = AppSettings.getStation();
    try {
      const passes = this.finder.getPasses(info.obj, station, now, MAX_WINDOW_H);
      info.pass = this.nextPass(passes, now);
    } catch (e) {
      // 保留旧预报
    }
  }

  private nextPass(passes: SatPassEvent[], now: number): SatPassEvent | null {
    for (let i = 0; i < passes.length; i++) {
      if (passes[i].losTime > now && passes[i].aosTime > now - 60000) {
        return passes[i];
      }
    }
    return null;
  }

  /** Center the viewport on the selected satellite's current ground position. */
  private followSelectedSat(): void {
    const pos = this.currentPosition();
    if (pos === null) {
      return;
    }
    this.viewCenterLon = this.wrapLon(toDegrees(pos.longitude));
    // keep the pole at/inside the map edge: never show latitude beyond ±90
    this.viewCenterLat = Math.max(-MAX_CENTER_LAT, Math.min(MAX_CENTER_LAT, toDegrees(pos.latitude)));
  }

  /** Wrap longitude to [-180, 180). */
  private wrapLon(lon: number): number {
    let v = lon;
    while (v >= 180.0) {
      v -= 360.0;
    }
    while (v < -180.0) {
      v += 360.0;
    }
    return v;
  }

  private fmtLat(lat: number): string {
    return `${Math.abs(lat).toFixed(1)}°${lat >= 0 ? 'N' : 'S'}`;
  }

  private fmtLon(lon: number): string {
    return `${Math.abs(lon).toFixed(1)}°${lon >= 0 ? 'E' : 'W'}`;
  }

  private selectedSat(): MapSatInfo | null {
    if (this.sats.length === 0 || this.selectedIndex < 0 || this.selectedIndex >= this.sats.length) {
      return null;
    }
    return this.sats[this.selectedIndex];
  }

  private selectPrev(): void {
    if (this.sats.length === 0) {
      return;
    }
    this.selectedIndex = (this.selectedIndex + this.sats.length - 1) % this.sats.length;
    this.refreshSelectedPass(true);
    this.followSelectedSat();
    this.updateLiveList();
    this.drawNow();
  }

  private selectNext(): void {
    if (this.sats.length === 0) {
      return;
    }
    this.selectedIndex = (this.selectedIndex + 1) % this.sats.length;
    this.refreshSelectedPass(true);
    this.followSelectedSat();
    this.updateLiveList();
    this.drawNow();
  }

  private findSat(all: SatOrbitalData[], catnum: number): SatOrbitalData | null {
    for (let i = 0; i < all.length; i++) {
      if (all[i].catnum === catnum) {
        return all[i];
      }
    }
    return null;
  }

  // ---- countdown ----

  private currentPosition(): SatOrbitalPos | null {
    const info = this.selectedSat();
    if (info === null) {
      return null;
    }
    const station = AppSettings.getStation();
    try {
      return info.obj.getFullPosition(station, this.nowTs);
    } catch (e) {
      hilog.warn(0x0001, 'MapPage', `pos fail ${info.name}`);
      return null;
    }
  }

  private countdownLabel(): string {
    const info = this.selectedSat();
    if (info === null || info.pass === null) {
      return '--:--:--';
    }
    const p = info.pass;
    if (this.nowTs < p.aosTime) {
      return this.fmtCountdown(p.aosTime - this.nowTs);
    }
    if (this.nowTs < p.losTime) {
      return this.fmtCountdown(p.losTime - this.nowTs);
    }
    return '--:--:--';
  }

  private countdownHint(): string {
    const info = this.selectedSat();
    if (info === null || info.pass === null) {
      return '待过境';
    }
    const p = info.pass;
    if (this.nowTs < p.aosTime) {
      return '距 AOS';
    }
    if (this.nowTs < p.losTime) {
      return '距 LOS';
    }
    return '待过境';
  }

  private fmtCountdown(ms: number): string {
    const s = Math.max(0, Math.floor(ms / 1000));
    const hh = Math.floor(s / 3600).toString().padStart(2, '0');
    const mm = Math.floor((s % 3600) / 60).toString().padStart(2, '0');
    const ss = (s % 60).toString().padStart(2, '0');
    return `${hh}:${mm}:${ss}`;
  }

  // ---- drawing ----

  private drawNow(): void {
    if (this.lastW > 0 && this.lastH > 0) {
      this.drawCanvas(this.lastW, this.lastH);
    }
  }

  private drawCanvas(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    try {
      this.renderCanvas(width, height);
    } catch (e) {
      hilog.error(0x0001, 'MapPage', `draw fail: ${JSON.stringify(e)}`);
    }
  }

  private renderCanvas(width: number, height: number): void {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = WATER_COLOR;
    ctx.fillRect(0, 0, width, height);
    this.drawGrid(ctx, width, height);

    ctx.fillStyle = LAND_COLOR;
    ctx.strokeStyle = BORDER_COLOR;
    ctx.lineWidth = 1;
    for (let i = 0; i < WORLD_RINGS.length; i++) {
      this.traceRing(ctx, WORLD_RINGS[i], width, height);
      ctx.fill();
      ctx.stroke();
    }

    const station = AppSettings.getStation();

    const info = this.selectedSat();
    if (info !== null) {
      this.drawTrack(ctx, info, width, height);

      const pos = this.currentPosition();
      if (pos !== null && pos.altitude > 0) {
        this.drawFootprint(ctx, pos, width, height);
      }
    }

    // live positions of all selected satellites.
    // Each satellite is isolated: a propagator error on one of them must not
    // abort the whole render (which left the footprint drawn without markers).
    for (let i = 0; i < this.sats.length; i++) {
      const sat = this.sats[i];
      let p: SatOrbitalPos;
      try {
        p = sat.obj.getFullPosition(station, this.nowTs);
      } catch (e) {
        hilog.warn(0x0001, 'MapPage', `marker fail ${sat.name}`);
        continue;
      }
      if (p.altitude <= 0) {
        continue;
      }
      const lon = this.wrapLon(toDegrees(p.longitude));
      const lat = toDegrees(p.latitude);
      if (!this.lonInView(lon) || !this.latInView(lat)) {
        continue;
      }
      const x = this.px(lon, width);
      const y = this.py(lat, height);
      const selected = i === this.selectedIndex;
      ctx.save();
      ctx.fillStyle = selected ? LIVE_COLOR : sat.color;
      ctx.strokeStyle = '#FFFFFF';
      ctx.lineWidth = selected ? 2 : 1;
      ctx.beginPath();
      ctx.arc(x, y, selected ? 6 : 4, 0, Math.PI * 2);
      ctx.fill();
      if (selected) {
        ctx.stroke();
      }
      ctx.restore();
    }

    // station marker
    const sx = this.px(station.longitude, width);
    const sy = this.py(station.latitude, height);
    ctx.save();
    ctx.fillStyle = STATION_COLOR;
    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(sx, sy, 5, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  /** Coverage circle of the satellite, longitudes unwrapped around the view center. */
  private drawFootprint(ctx: CanvasRenderingContext2D, pos: SatOrbitalPos, width: number, height: number): void {
    const circle = pos.getRangeCircle();
    if (circle.length === 0) {
      return;
    }
    ctx.save();
    ctx.strokeStyle = FOOTPRINT_COLOR;
    ctx.fillStyle = FOOTPRINT_COLOR;
    ctx.lineWidth = 1.5;
    let prev = circle[0].longitude;
    const shift = Math.round((this.viewCenterLon - prev) / 360.0) * 360.0;
    ctx.beginPath();
    for (let j = 0; j < circle.length; j++) {
      let lon = circle[j].longitude;
      while (lon - prev > 180.0) {
        lon -= 360.0;
      }
      while (lon - prev < -180.0) {
        lon += 360.0;
      }
      prev = lon;
      const x = this.pxRaw(lon + shift, width);
      const y = this.py(circle[j].latitude, height);
      if (j === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.closePath();
    ctx.globalAlpha = 0.18;
    ctx.fill();
    ctx.globalAlpha = 0.75;
    ctx.stroke();
    ctx.restore();
  }

  /**
   * Draw the future ground track of the selected satellite: only one continuous
   * line starting at the live position and running until it leaves the map.
   * Already-passed samples (behind the satellite) are not drawn. Longitudes are
   * unwrapped continuously so the line never breaks at the antimeridian or near
   * the poles where longitude changes fast.
   */
  private drawTrack(ctx: CanvasRenderingContext2D, info: MapSatInfo, width: number, height: number): void {
    const lons = info.lons;
    const lats = info.lats;
    const times = info.times;
    if (lons.length === 0) {
      return;
    }
    const half = this.lonSpan() / 2;
    const start = this.currentPosition();
    ctx.save();
    ctx.strokeStyle = TRACK_COLOR;
    ctx.lineWidth = 2.5;
    ctx.globalAlpha = 0.95;
    ctx.beginPath();
    let started = false;
    let prev = 0;
    for (let j = 0; j < lons.length; j++) {
      if (times[j] < this.nowTs) {
        continue; // already-passed portion of the orbit
      }
      let lon = lons[j];
      if (!started) {
        lon = this.relLon(lon);
      } else {
        while (lon - prev > 180.0) {
          lon -= 360.0;
        }
        while (lon - prev < -180.0) {
          lon += 360.0;
        }
      }
      const lat = lats[j];
      const inView = Math.abs(lon - this.viewCenterLon) <= half && this.latInView(lat);
      const x = this.pxRaw(lon, width);
      const y = this.py(lat, height);
      if (!started) {
        if (!inView) {
          prev = lon;
          continue;
        }
        if (start !== null) {
          // seamless: start the line at the live satellite position
          ctx.moveTo(this.pxRaw(this.relLon(this.wrapLon(toDegrees(start.longitude))), width),
            this.py(toDegrees(start.latitude), height));
          ctx.lineTo(x, y);
        } else {
          ctx.moveTo(x, y);
        }
        started = true;
        prev = lon;
        continue;
      }
      // extend the line through the map edge, then stop: later passes are not drawn
      ctx.lineTo(x, y);
      if (!inView) {
        break;
      }
      prev = lon;
    }
    if (started) {
      ctx.stroke();
    }
    ctx.restore();
  }

  private drawGrid(ctx: CanvasRenderingContext2D, width: number, height: number): void {
    ctx.save();
    ctx.strokeStyle = GRID_COLOR;
    ctx.lineWidth = 1;
    ctx.globalAlpha = 0.6;
    for (let lon = -180; lon <= 180; lon += 30) {
      const x = this.px(lon, width);
      if (x < 0 || x > width) {
        continue;
      }
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, height);
      ctx.stroke();
    }
    for (let lat = -90; lat <= 90; lat += 30) {
      const y = this.py(lat, height);
      if (y < 0 || y > height) {
        continue;
      }
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(width, y);
      ctx.stroke();
    }
    // latitude / longitude labels
    ctx.globalAlpha = 0.9;
    ctx.fillStyle = '#6E8BB5';
    ctx.font = '10px sans-serif';
    for (let lon = -180; lon <= 180; lon += 30) {
      const x = this.px(lon, width);
      if (x >= 24 && x <= width - 24) {
        ctx.fillText(this.fmtLon(lon), x - 16, 12);
      }
    }
    for (let lat = -90; lat <= 90; lat += 30) {
      const y = this.py(lat, height);
      if (y >= 22 && y <= height - 8) {
        ctx.fillText(this.fmtLat(lat), 4, y - 4);
      }
    }
    ctx.restore();
  }

  private traceRing(ctx: CanvasRenderingContext2D, ring: number[][], width: number, height: number): void {
    if (ring.length < 3) {
      return;
    }
    // Unwrap longitudes continuously and anchor the ring near the view center so
    // landmasses render correctly even when the viewport crosses the antimeridian.
    let prev = ring[0][0];
    const shift = Math.round((this.viewCenterLon - prev) / 360.0) * 360.0;
    ctx.beginPath();
    for (let i = 0; i < ring.length; i++) {
      let lon = ring[i][0];
      while (lon - prev > 180.0) {
        lon -= 360.0;
      }
      while (lon - prev < -180.0) {
        lon += 360.0;
      }
      prev = lon;
      const x = this.pxRaw(lon + shift, width);
      const y = this.py(ring[i][1], height);
      if (i === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.closePath();
  }

  /** Effective longitude span: widens by 1/cos(centerLat) so shapes keep true scale
   *  at high latitudes (a degree of longitude shrinks as you approach the pole). */
  private lonSpan(): number {
    const lat = Math.min(Math.abs(this.viewCenterLat), MAX_CENTER_LAT) * DEG2RAD;
    return BASE_LON_SPAN / Math.max(Math.cos(lat), 0.2);
  }

  /** Normalize [lon] into (viewCenterLon - 180, viewCenterLon + 180]. */
  private relLon(lon: number): number {
    let d = lon - this.viewCenterLon;
    while (d >= 180.0) {
      d -= 360.0;
    }
    while (d < -180.0) {
      d += 360.0;
    }
    return this.viewCenterLon + d;
  }

  private px(lon: number, width: number): number {
    return this.pxRaw(this.relLon(lon), width);
  }

  /** Map an already-unwrapped longitude linearly onto the canvas. */
  private pxRaw(lon: number, width: number): number {
    return (lon - (this.viewCenterLon - this.lonSpan() / 2)) / this.lonSpan() * width;
  }

  private py(lat: number, height: number): number {
    return ((this.viewCenterLat + VIEW_LAT_SPAN / 2) - lat) / VIEW_LAT_SPAN * height;
  }

  private lonInView(lon: number): boolean {
    return Math.abs(this.relLon(lon) - this.viewCenterLon) <= this.lonSpan() / 2;
  }

  private latInView(lat: number): boolean {
    return Math.abs(lat - this.viewCenterLat) <= VIEW_LAT_SPAN / 2;
  }

  // ---- info helpers ----

  private posText(): string {
    const pos = this.currentPosition();
    if (pos === null) {
      return '--';
    }
    return `${this.fmtLat(toDegrees(pos.latitude))} ${this.fmtLon(this.wrapLon(toDegrees(pos.longitude)))}`;
  }

  private qthText(): string {
    const pos = this.currentPosition();
    if (pos === null) {
      return '--';
    }
    return positionToQth(toDegrees(pos.latitude), this.wrapLon(toDegrees(pos.longitude))) ?? '--';
  }

  private stationText(): string {
    return `站 ${this.stationLat.toFixed(2)}, ${this.stationLon.toFixed(2)}`;
  }

  private stationQthText(): string {
    return `站QTH ${positionToQth(this.stationLat, this.stationLon) ?? '--'}`;
  }

  private rateText(): string {
    const pos = this.currentPosition();
    return pos === null ? '距变 --' : `距变 ${pos.distanceRate.toFixed(2)}km/s`;
  }

  private velocityText(): string {
    const pos = this.currentPosition();
    return pos === null ? '速度 --' : `速度 ${pos.getOrbitalVelocity().toFixed(2)}km/s`;
  }

  private shadowText(): string {
    const pos = this.currentPosition();
    return pos === null ? '光照 --' : (pos.eclipsed ? '地影中' : '光照中');
  }

  private statusText(): string {
    const pos = this.currentPosition();
    return pos === null ? '状态 --' : (pos.aboveHorizon ? '地平线上' : '地平线下');
  }

  private periodText(): string {
    const info = this.selectedSat();
    return info === null ? '周期 --' : `周期 ${info.obj.data.orbitalPeriod.toFixed(1)}分`;
  }

  private inclText(): string {
    const info = this.selectedSat();
    return info === null ? '倾角 --' : `倾角 ${info.obj.data.incl.toFixed(1)}°`;
  }

  private eccnText(): string {
    const info = this.selectedSat();
    return info === null ? '偏心 --' : `偏心 ${info.obj.data.eccn.toFixed(5)}`;
  }

  private meanmoText(): string {
    const info = this.selectedSat();
    return info === null ? '均动 --' : `均动 ${info.obj.data.meanmo.toFixed(2)}圈/天`;
  }

  private noradText(): string {
    const info = this.selectedSat();
    return info === null ? 'NORAD --' : `NORAD ${info.catnum}`;
  }

  /** Live az/el/range of every selected satellite for the details list. */
  private updateLiveList(): void {
    const station = AppSettings.getStation();
    const rows: MapLiveInfo[] = [];
    for (let i = 0; i < this.sats.length; i++) {
      const sat = this.sats[i];
      const row = new MapLiveInfo(sat.catnum, sat.name, sat.color);
      try {
        const p = sat.obj.getFullPosition(station, this.nowTs);
        row.az = `${toDegrees(p.azimuth).toFixed(0)}°`;
        row.el = `${toDegrees(p.elevation).toFixed(0)}°`;
        row.dist = `${p.distance.toFixed(0)}km`;
        row.above = p.aboveHorizon;
      } catch (e) {
        // keep placeholders
      }
      rows.push(row);
    }
    this.liveList = rows;
  }

  private phaseText(): string {
    const pos = this.currentPosition();
    if (pos === null) {
      return '--';
    }
    return `${toDegrees(pos.phase).toFixed(0)}°`;
  }

  private clock(millis: number): string {
    const d = new Date(millis);
    const hh = d.getHours().toString().padStart(2, '0');
    const mm = d.getMinutes().toString().padStart(2, '0');
    return `${hh}:${mm}`;
  }

  // ---- ui ----

  build() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Button('‹')
          .type(ButtonType.Circle)
          .width(40)
          .height(40)
          .fontSize(20)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.color_primary'))
          .enabled(this.sats.length > 0)
          .onClick((): void => {
            this.selectPrev()
          })
        Column({ space: 2 }) {
          Text(this.maybeName())
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 4 }) {
            Text(this.countdownHint())
              .fontSize(11)
              .fontColor($r('app.color.color_text_secondary'))
            Text(this.countdownLabel())
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.color_primary'))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        Button('›')
          .type(ButtonType.Circle)
          .width(40)
          .height(40)
          .fontSize(20)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.color_primary'))
          .enabled(this.sats.length > 0)
          .onClick((): void => {
            this.selectNext()
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 8, bottom: 0 })

      // China-viewport night map, moderate size (not stretched full screen)
      Stack() {
        Canvas(this.ctx)
          .width('100%')
          .height('100%')
          .onReady(() => {
            const w = Number(this.ctx.width);
            const h = Number(this.ctx.height);
            if (w > 0 && h > 0) {
              this.lastW = w;
              this.lastH = h;
              this.drawCanvas(w, h);
            }
          })
          .onAreaChange((oldValue: Area, newValue: Area) => {
            const w = Number(newValue.width);
            const h = Number(newValue.height);
            if (w > 0 && h > 0) {
              this.lastW = w;
              this.lastH = h;
              this.drawCanvas(w, h);
            }
          })
      }
      .width('100%')
      .aspectRatio(1.25)
      .clip(true)

      // Details panel: fills the remaining screen
      Column() {
        Scroll() {
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              Circle({ width: 10, height: 10 }).fill(this.maybeColor())
              Text(this.maybeName())
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.color_text'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.shadowText())
                .fontSize(12)
                .fontColor($r('app.color.color_text_secondary'))
              Text(this.statusText())
                .fontSize(12)
                .fontColor($r('app.color.color_primary'))
            }
            .width('100%')

            Row({ space: 6 }) {
              MapInfoChip({ text: this.azimuthText() })
              MapInfoChip({ text: this.elevationText() })
              MapInfoChip({ text: this.altitudeText() })
            }
            .width('100%')

            Row({ space: 6 }) {
              MapInfoChip({ text: this.rangeText() })
              MapInfoChip({ text: this.rateText() })
              MapInfoChip({ text: this.velocityText() })
            }
            .width('100%')

            Row({ space: 6 }) {
              MapInfoChip({ text: `相位 ${this.phaseText()}` })
              MapInfoChip({ text: this.shadowText() })
              MapInfoChip({ text: this.statusText() })
            }
            .width('100%')

            Row({ space: 6 }) {
              MapInfoChip({ text: `星下 ${this.posText()}` })
            }
            .width('100%')

            Row({ space: 6 }) {
              MapInfoChip({ text: `QTH ${this.qthText()}` })
              MapInfoChip({ text: this.nextPassShort() })
            }
            .width('100%')

            Row({ space: 6 }) {
              MapInfoChip({ text: this.periodText() })
              MapInfoChip({ text: this.inclText() })
              MapInfoChip({ text: this.eccnText() })
            }
            .width('100%')

            Row({ space: 6 }) {
              MapInfoChip({ text: this.meanmoText() })
              MapInfoChip({ text: this.noradText() })
              MapInfoChip({ text: this.stationText() })
            }
            .width('100%')

            Row({ space: 6 }) {
              MapInfoChip({ text: this.stationQthText() })
            }
            .width('100%')

            Divider()
              .color('#2A3B52')
              .margin({ top: 4, bottom: 2 })

            Text('已选卫星实时状态')
              .fontSize(12)
              .fontColor($r('app.color.color_text_secondary'))

            ForEach(this.liveList, (item: MapLiveInfo) => {
              Row({ space: 8 }) {
                Circle({ width: 8, height: 8 }).fill(item.color)
                Text(item.name)
                  .fontSize(13)
                  .fontColor($r('app.color.color_text'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`方位 ${item.az}`)
                  .fontSize(12)
                  .fontColor($r('app.color.color_text_secondary'))
                Text(`仰角 ${item.el}`)
                  .fontSize(12)
                  .fontColor($r('app.color.color_text_secondary'))
                Text(item.dist)
                  .fontSize(12)
                  .fontColor($r('app.color.color_text_secondary'))
                if (item.above) {
                  Text('可见')
                    .fontSize(11)
                    .fontColor($r('app.color.color_primary'))
                }
              }
              .width('100%')
              .padding({ top: 3, bottom: 3 })
            }, (item: MapLiveInfo) => item.catnum.toString())
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
      }
      .layoutWeight(1)
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.color_card'))
      .borderRadius(12)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_bg'))
  }

  private nextPassShort(): string {
    const info = this.selectedSat();
    if (info === null || info.pass === null) {
      return '下次 --';
    }
    return `下次 ${this.clock(info.pass.aosTime)}`;
  }

  private maybeName(): string {
    const info = this.selectedSat();
    return info === null ? '地图' : info.name;
  }

  private maybeColor(): string {
    const info = this.selectedSat();
    return info === null ? '#E67E22' : info.color;
  }

  private azimuthText(): string {
    const pos = this.currentPosition();
    return pos === null ? '方位 --' : `方位 ${toDegrees(pos.azimuth).toFixed(0)}°`;
  }

  private elevationText(): string {
    const pos = this.currentPosition();
    return pos === null ? '仰角 --' : `仰角 ${toDegrees(pos.elevation).toFixed(0)}°`;
  }

  private altitudeText(): string {
    const pos = this.currentPosition();
    return pos === null ? '高度 --' : `高度 ${pos.altitude.toFixed(0)}km`;
  }

  private rangeText(): string {
    const pos = this.currentPosition();
    return pos === null ? '距离 --' : `距离 ${pos.distance.toFixed(0)}km`;
  }
}