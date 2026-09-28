/*
 * Look4Sat. Calendar page: per-day count of satellites passing over the
 * station within the next 14 days, based on the selected satellites.
 */

import { SatelliteApp } from '../../common/SatelliteApp';
import { SelectedSats } from '../../common/SelectedSats';
import { AppSettings } from '../../common/AppSettings';
import { SatOrbitalData } from '../../domain/predict/OrbitalData';
import { createOrbitalObject } from '../../domain/predict/OrbitalFactory';
import { SatPassEvent, SatPassFinder } from '../../domain/predict/SatPassFinder';
import { SatOrbitalObject } from '../../domain/predict/OrbitalObject';

const FORECAST_DAYS = 14;
const MAX_CALC_SATS = 20;
const DAY_MS = 86400000;
const WEEK_LABELS: string[] = ['日', '一', '二', '三', '四', '五', '六'];

class DayStat {
  passCount: number = 0;
  satCats: number[] = [];
}

class CalCell {
  day: number;
  dateMillis: number;
  inMonth: boolean;
  isToday: boolean;
  inRange: boolean;
  satCount: number;
  passCount: number;

  constructor(day: number, dateMillis: number, inMonth: boolean, isToday: boolean,
              inRange: boolean, satCount: number, passCount: number) {
    this.day = day;
    this.dateMillis = dateMillis;
    this.inMonth = inMonth;
    this.isToday = isToday;
    this.inRange = inRange;
    this.satCount = satCount;
    this.passCount = passCount;
  }
}

class CalPass {
  catnum: number;
  name: string;
  pass: SatPassEvent;

  constructor(catnum: number, name: string, pass: SatPassEvent) {
    this.catnum = catnum;
    this.name = name;
    this.pass = pass;
  }
}

@Component
export struct CalendarPage {
  @State year: number = 2026;
  @State month: number = 0;
  @State weeks: CalCell[][] = [];
  @State dayList: CalPass[] = [];
  @State daySatCount: number = 0;
  @State dayPassCount: number = 0;
  @State computing: boolean = false;
  @State selectedMillis: number = 0;
  @StorageLink('selected_version') @Watch('recompute') selVersion: number = 0;
  @StorageLink('data_version') @Watch('recompute') dataVersion: number = 0;
  @StorageLink('settings_min_elevation') @Watch('recompute') minElevation: number = 5;
  @StorageLink('station_latitude') @Watch('recompute') stationLat: number = 48.2;
  @StorageLink('station_longitude') @Watch('recompute') stationLon: number = 16.37;

  private app: SatelliteApp = SatelliteApp.getInstance();
  private finder: SatPassFinder = new SatPassFinder();
  private stats: Map<number, DayStat> = new Map();
  private passesByDay: Map<number, CalPass[]> = new Map();
  private computeSeq: number = 0;
  private gridVersion: number = 0;

  aboutToAppear(): void {
    const now = new Date();
    this.year = now.getFullYear();
    this.month = now.getMonth();
    this.selectedMillis = this.dayStart(now.getTime());
    this.recompute();
  }

  recompute(): void {
    const seq = ++this.computeSeq;
    this.runCompute(seq);
  }

  private async runCompute(seq: number): Promise<void> {
    const cats = SelectedSats.getCats();
    const all = this.app.getStore().getAll();
    const station = AppSettings.getStation();
    const minElev = this.minElevation;
    const now = Date.now();
    this.stats = new Map();
    this.passesByDay = new Map();
    this.computing = cats.length > 0 && all.length > 0;
    this.rebuildCells();
    this.applyDaySelection();
    if (cats.length === 0 || all.length === 0) {
      return;
    }
    const used = cats.slice(0, MAX_CALC_SATS);
    for (let i = 0; i < used.length; i++) {
      const satData = this.findSat(all, used[i]);
      if (satData === null) {
        continue;
      }
      let obj: SatOrbitalObject;
      try {
        obj = createOrbitalObject(satData);
      } catch (e) {
        continue;
      }
      let passes: SatPassEvent[] = [];
      try {
        passes = this.finder.getPasses(obj, station, now, FORECAST_DAYS * 24);
      } catch (e) {
        continue;
      }
      for (let j = 0; j < passes.length; j++) {
        const p = passes[j];
        if (p.maxElevationDeg < minElev) {
          continue;
        }
        const key = this.dayStart(p.aosTime);
        let stat = this.stats.get(key);
        if (stat === undefined) {
          stat = new DayStat();
          this.stats.set(key, stat);
        }
        stat.passCount++;
        if (stat.satCats.indexOf(used[i]) < 0) {
          stat.satCats.push(used[i]);
        }
        let list = this.passesByDay.get(key);
        if (list === undefined) {
          list = [];
          this.passesByDay.set(key, list);
        }
        list.push(new CalPass(used[i], satData.name, p));
      }
      await this.yieldFrame();
      if (seq !== this.computeSeq) {
        return;
      }
      this.rebuildCells();
      this.applyDaySelection();
    }
    this.computing = false;
    this.rebuildCells();
    this.applyDaySelection();
  }

  private yieldFrame(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout((): void => {
        resolve();
      }, 0);
    });
  }

  private dayStart(millis: number): number {
    const d = new Date(millis);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  }

  private todayStart(): number {
    return this.dayStart(Date.now());
  }

  private inForecast(dateMillis: number): boolean {
    const diff = Math.round((dateMillis - this.todayStart()) / DAY_MS);
    return diff >= 0 && diff < FORECAST_DAYS;
  }

  private rebuildCells(): void {
    this.gridVersion++;
    const cells: CalCell[][] = [];
    const first = new Date(this.year, this.month, 1);
    const offset = first.getDay();
    const todayStart = this.todayStart();
    const gridStart = this.dayStart(new Date(this.year, this.month, 1 - offset).getTime());
    for (let w = 0; w < 6; w++) {
      const week: CalCell[] = [];
      for (let d = 0; d < 7; d++) {
        const dateMillis = this.dayStart(gridStart + (w * 7 + d) * DAY_MS);
        const cd = new Date(dateMillis);
        const inMonth = cd.getMonth() === this.month && cd.getFullYear() === this.year;
        const isToday = dateMillis === todayStart;
        const inRange = this.inForecast(dateMillis);
        let satCount = 0;
        let passCount = 0;
        const stat = this.stats.get(dateMillis);
        if (stat !== undefined) {
          satCount = stat.satCats.length;
          passCount = stat.passCount;
        }
        week.push(new CalCell(cd.getDate(), dateMillis, inMonth, isToday, inRange, satCount, passCount));
      }
      cells.push(week);
    }
    this.weeks = cells;
  }

  private prevMonth(): void {
    let y = this.year;
    let m = this.month - 1;
    if (m < 0) {
      m = 11;
      y--;
    }
    this.year = y;
    this.month = m;
    this.fixSelectionForMonth();
    this.rebuildCells();
    this.applyDaySelection();
  }

  private nextMonth(): void {
    let y = this.year;
    let m = this.month + 1;
    if (m > 11) {
      m = 0;
      y++;
    }
    this.year = y;
    this.month = m;
    this.fixSelectionForMonth();
    this.rebuildCells();
    this.applyDaySelection();
  }

  private canPrev(): boolean {
    const t = new Date();
    return this.year > t.getFullYear() || (this.year === t.getFullYear() && this.month > t.getMonth());
  }

  private canNext(): boolean {
    const end = new Date(this.todayStart() + (FORECAST_DAYS - 1) * DAY_MS);
    return this.year < end.getFullYear() || (this.year === end.getFullYear() && this.month < end.getMonth());
  }

  private fixSelectionForMonth(): void {
    const sel = new Date(this.selectedMillis);
    if (sel.getFullYear() === this.year && sel.getMonth() === this.month) {
      return;
    }
    const daysInMonth = new Date(this.year, this.month + 1, 0).getDate();
    let pick = -1;
    for (let d = 1; d <= daysInMonth; d++) {
      const m = new Date(this.year, this.month, d).getTime();
      if (this.inForecast(m)) {
        pick = m;
        break;
      }
    }
    if (pick < 0) {
      pick = new Date(this.year, this.month, 1).getTime();
    }
    this.selectedMillis = pick;
  }

  private selectDay(cell: CalCell): void {
    if (!cell.inMonth) {
      return;
    }
    this.selectedMillis = cell.dateMillis;
    this.gridVersion++;
    this.applyDaySelection();
  }

  private applyDaySelection(): void {
    let list = this.passesByDay.get(this.selectedMillis);
    if (list === undefined) {
      list = [];
    }
    const sorted = Array.from(list);
    sorted.sort((a: CalPass, b: CalPass): number => b.pass.maxElevationDeg - a.pass.maxElevationDeg);
    this.dayList = sorted;
    const satCats: number[] = [];
    for (let i = 0; i < sorted.length; i++) {
      if (satCats.indexOf(sorted[i].catnum) < 0) {
        satCats.push(sorted[i].catnum);
      }
    }
    this.daySatCount = satCats.length;
    this.dayPassCount = sorted.length;
  }

  private findSat(all: SatOrbitalData[], catnum: number): SatOrbitalData | null {
    for (let i = 0; i < all.length; i++) {
      if (all[i].catnum === catnum) {
        return all[i];
      }
    }
    return null;
  }

  private isSelected(cell: CalCell): boolean {
    return cell.dateMillis === this.selectedMillis && cell.inMonth;
  }

  private hasSelection(): boolean {
    return SelectedSats.getCats().length > 0;
  }

  private hasData(): boolean {
    return this.app.getStore().getAll().length > 0;
  }

  private monthTitle(): string {
    return `${this.year}年${this.month + 1}月`;
  }

  private rangeTitle(): string {
    return `未来${FORECAST_DAYS}天 · 仰角≥${this.minElevation}°`;
  }

  private dayTitle(): string {
    const d = new Date(this.selectedMillis);
    const wd = WEEK_LABELS[d.getDay()];
    const rel = this.selectedMillis === this.todayStart() ? '今天 · ' : '';
    return `${rel}${d.getMonth() + 1}月${d.getDate()}日 · 周${wd}`;
  }

  private daySummary(): string {
    if (!this.inForecast(this.selectedMillis)) {
      return `超出${FORECAST_DAYS}天预报范围`;
    }
    return `${this.daySatCount} 颗卫星 · ${this.dayPassCount} 次过境`;
  }

  private clock(millis: number): string {
    const d = new Date(millis);
    const hh = d.getHours().toString().padStart(2, '0');
    const mm = d.getMinutes().toString().padStart(2, '0');
    return `${hh}:${mm}`;
  }

  build() {
    Column() {
      this.headerBar()
      this.weekHeader()
      this.gridArea()
      Divider()
        .color('#2A3B52')
        .margin({ top: 4, bottom: 4 })
      this.dayDetail()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_bg'))
  }

  @Builder
  private headerBar() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Button('‹')
          .type(ButtonType.Circle)
          .width(32)
          .height(32)
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.color_primary'))
          .enabled(this.canPrev())
          .opacity(this.canPrev() ? 1 : 0.35)
          .onClick((): void => {
            this.prevMonth()
          })
        Text(this.monthTitle())
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.color_text'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Button('›')
          .type(ButtonType.Circle)
          .width(32)
          .height(32)
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.color_primary'))
          .enabled(this.canNext())
          .opacity(this.canNext() ? 1 : 0.35)
          .onClick((): void => {
            this.nextMonth()
          })
      }
      .width('100%')

      Row({ space: 6 }) {
        Text(this.rangeTitle())
          .fontSize(11)
          .fontColor($r('app.color.color_text_secondary'))
        if (this.computing) {
          LoadingProgress()
            .width(12)
            .height(12)
            .color($r('app.color.color_primary'))
          Text('计算中…')
            .fontSize(11)
            .fontColor($r('app.color.color_text_secondary'))
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 4 })
  }

  @Builder
  private weekHeader() {
    Row() {
      ForEach(WEEK_LABELS, (label: string) => {
        Text(label)
          .fontSize(11)
          .fontColor($r('app.color.color_text_secondary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
      }, (label: string): string => label)
    }
    .width('100%')
    .padding({ left: 8, right: 8 })
  }

  @Builder
  private gridArea() {
    Column() {
      ForEach(this.weeks, (week: CalCell[]) => {
        Row() {
          ForEach(week, (cell: CalCell) => {
            Column({ space: 2 }) {
              Text(String(cell.day))
                .fontSize(13)
                .fontWeight(cell.isToday || this.isSelected(cell) ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.cellTextColor(cell))
              if (cell.inRange && cell.passCount > 0) {
                Text(`${cell.satCount}星`)
                  .fontSize(9)
                  .fontColor(Color.White)
                  .backgroundColor($r('app.color.color_primary'))
                  .borderRadius(7)
                  .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              }
            }
            .layoutWeight(1)
            .height(46)
            .justifyContent(FlexAlign.Center)
            .borderRadius(8)
            .backgroundColor(this.isSelected(cell) ? $r('app.color.color_card') : Color.Transparent)
            .onClick((): void => {
              this.selectDay(cell)
            })
          }, (cell: CalCell): string => `${this.gridVersion}-${cell.dateMillis}`)
        }
        .width('100%')
      }, (week: CalCell[]): string => `${this.year}-${this.month}-${this.gridVersion}-${week[0].dateMillis}`)
    }
    .width('100%')
    .padding({ left: 8, right: 8 })
  }

  private cellTextColor(cell: CalCell): ResourceColor {
    if (this.isSelected(cell)) {
      return $r('app.color.color_primary');
    }
    if (cell.isToday) {
      return $r('app.color.color_primary');
    }
    if (!cell.inMonth) {
      return '#5A6B80';
    }
    return $r('app.color.color_text');
  }

  @Builder
  private dayDetail() {
    Column({ space: 8 }) {
      Row() {
        Text(this.dayTitle())
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.color_text'))
        Blank()
        Text(this.daySummary())
          .fontSize(11)
          .fontColor($r('app.color.color_text_secondary'))
      }
      .width('100%')

      if (!this.hasData()) {
        Text('卫星数据加载中…')
          .fontSize(12)
          .fontColor($r('app.color.color_text_secondary'))
          .width('100%')
          .padding({ top: 20, bottom: 20 })
          .textAlign(TextAlign.Center)
      } else if (!this.hasSelection()) {
        Text('请在“卫星”标签页选择要跟踪的卫星')
          .fontSize(12)
          .fontColor($r('app.color.color_text_secondary'))
          .width('100%')
          .padding({ top: 20, bottom: 20 })
          .textAlign(TextAlign.Center)
      } else if (this.dayList.length === 0) {
        Text(this.inForecast(this.selectedMillis) ? '当日暂无达标过境' : '该日期超出预报范围')
          .fontSize(12)
          .fontColor($r('app.color.color_text_secondary'))
          .width('100%')
          .padding({ top: 20, bottom: 20 })
          .textAlign(TextAlign.Center)
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.dayList, (cp: CalPass) => {
              Row({ space: 10 }) {
                Column({ space: 2 }) {
                  Text(cp.name)
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.color_text'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`NORAD ${cp.catnum}`)
                    .fontSize(10)
                    .fontColor($r('app.color.color_text_secondary'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text(`${this.clock(cp.pass.aosTime)} - ${this.clock(cp.pass.losTime)}`)
                  .fontSize(12)
                  .fontColor($r('app.color.color_text'))
                Text(`最高 ${cp.pass.maxElevationDeg.toFixed(0)}°`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(cp.pass.maxElevationDeg > 45 ? '#2ECC71' : $r('app.color.color_primary'))
              }
              .width('100%')
              .padding(10)
              .backgroundColor($r('app.color.color_card'))
              .borderRadius(8)
            }, (cp: CalPass): string => `${cp.catnum}-${cp.pass.aosTime}`)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
      }
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ left: 14, right: 14, top: 4, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }
}
