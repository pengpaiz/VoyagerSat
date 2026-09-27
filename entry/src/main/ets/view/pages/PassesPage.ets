import { SatelliteApp } from '../../common/SatelliteApp';
import { SelectedSats } from '../../common/SelectedSats';
import { AppSettings, PassSortMode } from '../../common/AppSettings';
import { SatOrbitalData } from '../../domain/predict/OrbitalData';
import { createOrbitalObject } from '../../domain/predict/OrbitalFactory';
import { SatPassEvent, SatPassFinder } from '../../domain/predict/SatPassFinder';
import { PassDetailSheet, PassDetailPayload } from '../components/PassDetailSheet';
import { hilog } from '@kit.PerformanceAnalysisKit';

const SAT_COLORS: string[] = [
  '#0A59F7', '#E67E22', '#2ECC71', '#E74C3C', '#8E44AD', '#16A085',
  '#F39C12', '#3498DB', '#C0392B', '#27AE60', '#9B59B6', '#7F8C8D'
];

const MAX_WINDOW_H = 48;

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

@Component
export struct PassesPage {
  @State groups: PassSat[] = [];
  @State flatPasses: FlatPass[] = [];
  @StorageLink('selected_version') @Watch('recompute') selVersion: number = 0;
  @StorageLink('data_version') @Watch('recompute') dataVersion: number = 0;
  @StorageLink('settings_window_hours') @Watch('recompute') windowHours: number = 24;
  @StorageLink('settings_min_elevation') @Watch('recompute') minElevation: number = 5;
  @StorageLink('settings_pass_sort') @Watch('recompute') sortMode: number = PassSortMode.BY_SATELLITE;

  @State showDetail: boolean = false;
  @State detailPayload: PassDetailPayload = new PassDetailPayload();
  @State detailOpenSeq: number = 0;
  @State trackCount: number = 0;
  @State nowTs: number = Date.now();

  private app: SatelliteApp = SatelliteApp.getInstance();
  private finder: SatPassFinder = new SatPassFinder();

  aboutToAppear(): void {
    this.recompute();
  }

  recompute(): void {
    const cats = SelectedSats.getCats();
    this.trackCount = cats.length;
    this.nowTs = Date.now();
    if (cats.length === 0) {
      this.groups = [];
      this.flatPasses = [];
      return;
    }
    const store = this.app.getStore();
    const station = AppSettings.getStation();
    const allCats = store.getAll();
    const satList: PassSat[] = [];
    for (let i = 0; i < cats.length; i++) {
      const cat = cats[i];
      const satData = this.findSat(allCats, cat);
      if (satData === null) {
        continue;
      }
      const obj = createOrbitalObject(satData);
      const passes = this.finder.getPasses(obj, station, this.nowTs, MAX_WINDOW_H);
      satList.push(new PassSat(cat, satData.name, SAT_COLORS[i % SAT_COLORS.length], passes));
    }

    if (this.sortMode === PassSortMode.BY_SATELLITE) {
      satList.sort((a: PassSat, b: PassSat): number => a.name.localeCompare(b.name));
      this.groups = satList;
      this.flatPasses = [];
    } else {
      const flat: FlatPass[] = [];
      for (let i = 0; i < satList.length; i++) {
        const s = satList[i];
        for (let j = 0; j < s.passes.length; j++) {
          flat.push(new FlatPass(s.catnum, s.name, s.color, s.passes[j]));
        }
      }
      flat.sort((a: FlatPass, b: FlatPass): number => a.pass.aosTime - b.pass.aosTime);
      this.flatPasses = flat;
      this.groups = [];
    }
  }

  private findSat(all: SatOrbitalData[], catnum: number): SatOrbitalData | null {
    for (let i = 0; i < all.length; i++) {
      if (all[i].catnum === catnum) {
        return all[i];
      }
    }
    return null;
  }

  private openDetail(catnum: number, pass: SatPassEvent, color: string): void {
    this.detailOpenSeq++;
    const seq = this.detailOpenSeq;
    const payload = PassDetailSheet.buildPayload(catnum, pass, color);
    this.detailPayload = payload;
    this.showDetail = true;
    hilog.info(0x0001, 'PassOpen', `seq=${seq} cat=${catnum} name=${payload.name} show=${this.showDetail}`);
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
      if (this.hasData()) {
        if (this.sortMode === PassSortMode.BY_SATELLITE) {
          this.satelliteView()
        } else {
          this.flatTimeView()
        }
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

  private hasData(): boolean {
    if (this.sortMode === PassSortMode.BY_SATELLITE) {
      return this.groups.length > 0;
    }
    return this.visibleFlatCount() > 0;
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
    Row() {
      Text('过境预报').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.color_text'))
      Blank()
      Text(`仰角>=${this.minElevation}deg · ${this.windowHours}h · ${this.trackCount}星`)
        .fontSize(11)
        .fontColor($r('app.color.color_text_secondary'))
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 6 })
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
      .padding(14)
    }
    .layoutWeight(1)
    .width('100%')
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
      .padding(14)
    }
    .layoutWeight(1)
    .width('100%')
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
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private passRow(catnum: number, p: SatPassEvent, color: string) {
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
          .fontColor(p.maxElevationDeg > 45 ? '#2ECC71' : color as ResourceColor)
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
    .padding(10)
    .backgroundColor($r('app.color.color_bg'))
    .borderRadius(8)
    .onClick((): void => {
      this.openDetail(catnum, p, color)
    })
  }

  @Builder
  private flatRow(f: FlatPass) {
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
          .fontColor(f.pass.maxElevationDeg > 45 ? '#2ECC71' : f.color as ResourceColor)
      }
      .alignItems(HorizontalAlign.End)

      Text('>')
        .fontSize(18)
        .fontColor($r('app.color.color_text_secondary'))
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(10)
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