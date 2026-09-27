/*
 * Look4Sat. Amateur radio satellite tracker and pass predictor.
 * Application-scoped singleton wiring data layer together.
 */

import { common } from '@kit.AbilityKit';
import { SatelliteStore } from '../data/storage/SatelliteStore';
import { SatelliteDownloader } from '../data/downloader/SatelliteDownloader';
import { SatelliteImporter } from '../data/importer/SatelliteImporter';
import { SatOrbitalData } from '../domain/predict/OrbitalData';
import { SatGeoPos } from '../domain/predict/GeoPos';
import { Locator } from './Locator';
import { AppSettings } from './AppSettings';

const STATION_LAT = 'station_latitude';
const STATION_LON = 'station_longitude';
const STATION_ALT = 'station_altitude';

export const ISS_CATNUM = 25544;

export class SatelliteApp {
  private static instanceValue: SatelliteApp | null = null;
  private store: SatelliteStore = new SatelliteStore();
  private downloader: SatelliteDownloader = new SatelliteDownloader();
  private importer: SatelliteImporter = new SatelliteImporter();
  private startupDone: boolean = false;
  private ctx: common.Context | null = null;

  static getInstance(): SatelliteApp {
    if (SatelliteApp.instanceValue === null) {
      SatelliteApp.instanceValue = new SatelliteApp();
    }
    return SatelliteApp.instanceValue;
  }

  init(context: common.Context): void {
    this.store.setContext(context);
    this.ctx = context;
  }

  getStore(): SatelliteStore {
    return this.store;
  }

  async loadFromDisk(): Promise<void> {
    await this.store.load();
  }

  /** 启动时静默执行：静默更新数据（不提示），并尝试定位更新站址。 */
  async silentStartupUpdate(): Promise<void> {
    if (this.startupDone) {
      return;
    }
    this.startupDone = true;
    // 静默下载（若已有数据则仍刷新一次）
    try {
      const result = await this.downloader.downloadFromMirror();
      this.store.replaceAll(result.dataList);
      this.store.dedupeKeepFreshest();
      await this.store.save();
    } catch (e) {
      // 静默忽略下载失败
    }
    try {
      const t = await this.downloader.downloadTransponders();
      this.store.setTransponders(t.transponders);
      await this.store.saveTransponders();
    } catch (e) {
      // 静默忽略转发器失败
    }
    // 静默尝试定位（若权限允许）
    if (this.ctx !== null) {
      try {
        const pos = await Locator.getCurrentPosition(this.ctx);
        if (pos !== null) {
          AppSettings.setStation(pos.latitude, pos.longitude, pos.altitude);
        }
      } catch (e) {
        // 静默忽略定位失败
      }
    }
  }

  async downloadAndStore(): Promise<number> {
    const result = await this.downloader.downloadFromMirror();
    this.store.replaceAll(result.dataList);
    this.store.dedupeKeepFreshest();
    await this.store.save();
    this.bumpDataVersion();
    return this.store.getAll().length;
  }

  private bumpDataVersion(): void {
    const v = AppStorage.get<number>('data_version') ?? 0;
    AppStorage.setOrCreate<number>('data_version', v + 1);
  }

  /** 下载转发器数据（国内加速镜像）到 store，返回条数。 */
  async downloadTranspondersAndStore(): Promise<number> {
    const result = await this.downloader.downloadTransponders();
    this.store.setTransponders(result.transponders);
    await this.store.saveTransponders();
    return result.count;
  }

  async importAndStore(context: common.Context): Promise<number> {
    const result = await this.importer.pickAndParse(context);
    if (result === null) {
      return -1;
    }
    this.store.replaceAll(result.dataList);
    this.store.dedupeKeepFreshest();
    await this.store.save();
    this.bumpDataVersion();
    return this.store.getAll().length;
  }

  downloadFromMirror(): Promise<number> {
    return this.downloadAndStore();
  }

  getDownloader(): SatelliteDownloader {
    return this.downloader;
  }

  getImporter(): SatelliteImporter {
    return this.importer;
  }

  getStation(): SatGeoPos {
    const lat = AppStorage.get<number>(STATION_LAT);
    const lon = AppStorage.get<number>(STATION_LON);
    const alt = AppStorage.get<number>(STATION_ALT);
    return new SatGeoPos(
      lat === undefined ? 48.2 : lat,
      lon === undefined ? 16.37 : lon,
      alt === undefined ? 0 : alt,
      'station'
    );
  }

  getCatalogPreview(list: SatOrbitalData[]): string {
    if (list.length === 0) {
      return '无卫星数据';
    }
    return `共 ${list.length} 颗卫星`;
  }
}