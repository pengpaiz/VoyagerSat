/*
 * Look4Sat. 过境预报（48h 窗口）的共享缓存。
 *
 * 目的：过境页原来每次重算都对**每颗**已选星同步跑一遍 getPasses(48h)，
 * 选的星一多，启动/切页就会出现长时间卡顿。
 * 这里把「单颗星 48h 过境」缓存起来：
 * - 只有新选中的星需要补算，其余直接命中；
 * - 窗口(12/24/48h)与仰角门槛只影响显示过滤，不影响这里的计算，所以整份缓存通吃；
 * - 签名按小时分桶（数据/站址/小时任一变化即作废），既不过期太久也不必频繁重算。
 */

import { SatOrbitalData } from './OrbitalData';
import { SatGeoPos } from './GeoPos';
import { SatPassEvent, SatPassFinder } from './SatPassFinder';
import { createOrbitalObject } from './OrbitalFactory';
import { AppSettings } from '../../common/AppSettings';

/** 统一按最长窗口计算，短窗口只在显示时过滤 */
export const PASS_CACHE_HOURS = 48;

class CachedPasses {
  name: string = '';
  passes: SatPassEvent[] = [];

  constructor(name: string, passes: SatPassEvent[]) {
    this.name = name;
    this.passes = passes;
  }
}

export class PassCache {
  private static instanceValue: PassCache | null = null;
  private cache: Map<number, CachedPasses> = new Map<number, CachedPasses>();
  private signature: string = '';
  private finder: SatPassFinder = new SatPassFinder();

  static getInstance(): PassCache {
    if (PassCache.instanceValue === null) {
      PassCache.instanceValue = new PassCache();
    }
    return PassCache.instanceValue;
  }

  /** 缓存签名：数据版本 + 站址 + 当前小时（按小时分桶）。 */
  static signatureOf(dataVersion: number): string {
    const st = AppSettings.getStation();
    const hour = Math.floor(Date.now() / 3600000);
    return `${dataVersion}|${st.latitude}|${st.longitude}|${st.altitude}|${hour}`;
  }

  /** 页面侧调用：签名变化时清空缓存。 */
  prepare(dataVersion: number): void {
    const sig = PassCache.signatureOf(dataVersion);
    if (sig !== this.signature) {
      this.cache.clear();
      this.signature = sig;
    }
  }

  has(catnum: number): boolean {
    return this.cache.has(catnum);
  }

  nameOf(catnum: number): string {
    const c = this.cache.get(catnum);
    return c === undefined ? '' : c.name;
  }

  passesOf(catnum: number): SatPassEvent[] {
    const c = this.cache.get(catnum);
    return c === undefined ? [] : c.passes;
  }

  /** 星在库里找不到时也记一笔空缓存，避免反复重试。 */
  markMissing(catnum: number): void {
    this.cache.set(catnum, new CachedPasses('', []));
  }

  /** 单颗星计算并入缓存（同步，调用方负责让帧）。 */
  computeOne(catnum: number, satData: SatOrbitalData, station: SatGeoPos, now: number): void {
    let passes: SatPassEvent[] = [];
    try {
      const obj = createOrbitalObject(satData);
      passes = this.finder.getPasses(obj, station, now, PASS_CACHE_HOURS);
    } catch (e) {
      passes = [];
    }
    this.cache.set(catnum, new CachedPasses(satData.name, passes));
  }
}
