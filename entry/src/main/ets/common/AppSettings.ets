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
  }

  static getStation(): SatGeoPos {
    return new SatGeoPos(
      AppStorage.get<number>(K_LAT) ?? 48.2,
      AppStorage.get<number>(K_LON) ?? 16.37,
      AppStorage.get<number>(K_ALT) ?? 0,
      'station'
    );
  }

  static setStation(lat: number, lon: number, alt: number): void {
    AppStorage.setOrCreate<number>(K_LAT, lat);
    AppStorage.setOrCreate<number>(K_LON, lon);
    AppStorage.setOrCreate<number>(K_ALT, alt);
    const qth = positionToQth(lat, lon);
    if (qth !== null) {
      AppStorage.setOrCreate<string>(K_QTH, qth);
    }
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