/*
 * Look4Sat. Shared app settings (station, forecast params) across tabs.
 * Persisted in AppStorage so values survive tab switches and re-render reactively.
 */

import { SatGeoPos } from '../domain/predict/GeoPos';
import { positionToQth } from '../domain/qth/QthConverter';

const K_LAT = 'station_latitude';
const K_LON = 'station_longitude';
const K_ALT = 'station_altitude';
const K_QTH = 'station_qth';
const K_MIN_ELEV = 'settings_min_elevation';
const K_WINDOW_H = 'settings_window_hours';
const K_SORT = 'settings_pass_sort';
const K_STATION_VER = 'station_version';
/** 站址是否由用户手动设置过：是则启动静默定位不再覆盖 */
const K_STATION_MANUAL = 'station_manual';
/** 自定义数据源 URL（空 = 使用内置镜像） */
const K_TLE_URL = 'settings_custom_tle_url';
const K_TRANS_URL = 'settings_custom_transponder_url';

export enum PassSortMode {
  BY_SATELLITE = 0,
  BY_TIME = 1
}

export const WINDOW_PRESETS: number[] = [12, 24, 48];

export class AppSettings {
  static init(): void {
    PersistentStorage.persistProp(K_LAT, 48.2);
    PersistentStorage.persistProp(K_LON, 16.37);
    PersistentStorage.persistProp(K_ALT, 0);
    PersistentStorage.persistProp(K_MIN_ELEV, 5);
    PersistentStorage.persistProp(K_WINDOW_H, 24);
    PersistentStorage.persistProp(K_SORT, PassSortMode.BY_SATELLITE);
    PersistentStorage.persistProp(K_QTH, '');
    PersistentStorage.persistProp(K_TLE_URL, '');
    PersistentStorage.persistProp(K_TRANS_URL, '');
    PersistentStorage.persistProp(K_STATION_MANUAL, false);
    if (AppStorage.get<number>(K_STATION_VER) === undefined) {
      AppStorage.setOrCreate<number>(K_STATION_VER, 0);
    }
  }

  /** 站址变更版本号：设置页据此刷新已显示的经纬度/海拔，避免显示过期值。 */
  static getStationVersion(): number {
    return AppStorage.get<number>(K_STATION_VER) ?? 0;
  }

  static getStation(): SatGeoPos {
    return new SatGeoPos(
      AppStorage.get<number>(K_LAT) ?? 48.2,
      AppStorage.get<number>(K_LON) ?? 16.37,
      AppStorage.get<number>(K_ALT) ?? 0,
      'station'
    );
  }

  /** [manual] 为 true 表示用户手动设定，启动静默定位不再覆盖该站址。 */
  static setStation(lat: number, lon: number, alt: number, manual: boolean = false): void {
    AppStorage.setOrCreate<number>(K_LAT, lat);
    AppStorage.setOrCreate<number>(K_LON, lon);
    AppStorage.setOrCreate<number>(K_ALT, alt);
    if (manual) {
      AppStorage.setOrCreate<boolean>(K_STATION_MANUAL, true);
    }
    const qth = positionToQth(lat, lon);
    if (qth !== null) {
      AppStorage.setOrCreate<string>(K_QTH, qth);
    }
    AppStorage.setOrCreate<number>(K_STATION_VER, AppSettings.getStationVersion() + 1);
  }

  /** 用户是否手动设定过站址。 */
  static isStationManual(): boolean {
    return AppStorage.get<boolean>(K_STATION_MANUAL) ?? false;
  }

  /** 自定义 TLE 数据源；返回空串表示未设置（用内置镜像）。 */
  static getCustomTleUrl(): string {
    return AppStorage.get<string>(K_TLE_URL) ?? '';
  }

  static setCustomTleUrl(url: string): void {
    AppStorage.setOrCreate<string>(K_TLE_URL, url.trim());
  }

  /** 自定义转发器 JSON 数据源；返回空串表示未设置。 */
  static getCustomTransponderUrl(): string {
    return AppStorage.get<string>(K_TRANS_URL) ?? '';
  }

  static setCustomTransponderUrl(url: string): void {
    AppStorage.setOrCreate<string>(K_TRANS_URL, url.trim());
  }

  static getMinElevation(): number {
    return AppStorage.get<number>(K_MIN_ELEV) ?? 5;
  }

  static setMinElevation(v: number): void {
    AppStorage.setOrCreate<number>(K_MIN_ELEV, v);
  }

  static getWindowHours(): number {
    return AppStorage.get<number>(K_WINDOW_H) ?? 48;
  }

  static setWindowHours(v: number): void {
    AppStorage.setOrCreate<number>(K_WINDOW_H, v);
  }

  static getSortMode(): number {
    return AppStorage.get<number>(K_SORT) ?? PassSortMode.BY_TIME;
  }

  static setSortMode(mode: number): void {
    AppStorage.setOrCreate<number>(K_SORT, mode);
  }
}