/*
 * Look4Sat. Amateur radio satellite tracker and pass predictor.
 * HarmonyOS data layer: download TLE/OMM from Celestrak/SatNOGS.
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SatDataParser } from '../../domain/parser/DataParser';
import { SatOrbitalData } from '../../domain/predict/OrbitalData';
import { SatRadio } from '../../domain/model/SatRadio';
import { bytesToString } from '../../common/utils/TextUtils';

export const CN_TLE_URL = 'https://tledata.xanyi.eu.org/tledata/all.txt';
export const CN_TRANSPONDER_URL = 'https://tledata.xanyi.eu.org/tledata/trans.json';
export const CELESTRAK_CSV_URL = 'https://celestrak.org/NORAD/elements/gp.php?GROUP=active&FORMAT=csv';
export const CELESTRAK_TLE_URL = 'https://celestrak.org/NORAD/elements/gp.php?GROUP=active&FORMAT=tle';

export class SatelliteDownloadResult {
  dataList: SatOrbitalData[];
  count: number;

  constructor(dataList: SatOrbitalData[]) {
    this.dataList = dataList;
    this.count = dataList.length;
  }
}

export class TransponderDownloadResult {
  transponders: SatRadio[];
  count: number;

  constructor(transponders: SatRadio[]) {
    this.transponders = transponders;
    this.count = transponders.length;
  }
}

export class SatelliteDownloader {
  private parser: SatDataParser = new SatDataParser();

  async downloadTLE(url: string = CELESTRAK_TLE_URL): Promise<SatelliteDownloadResult> {
    const text = await this.fetchText(url);
    const list = this.parser.parseTLEStream(text);
    return new SatelliteDownloadResult(list);
  }

  async downloadCSV(url: string = CELESTRAK_CSV_URL): Promise<SatelliteDownloadResult> {
    const text = await this.fetchText(url);
    const list = this.parser.parseCSVStream(text);
    return new SatelliteDownloadResult(list);
  }

  /** Download satellites from the domestic accelerated mirror (all.txt, TLE 3-line). */
  async downloadFromMirror(url: string = CN_TLE_URL): Promise<SatelliteDownloadResult> {
    const text = await this.fetchText(url);
    const list = this.parser.parseTLEStream(text);
    return new SatelliteDownloadResult(list);
  }

  /** Multi-source download: try mirror first, then Celestrak fallback. */
  async downloadWithFallback(customUrl: string = ''): Promise<SatelliteDownloadResult> {
    const sources: string[] = [];
    if (customUrl.trim().length > 0) {
      sources.push(customUrl.trim());
    }
    sources.push(CN_TLE_URL);
    sources.push(CELESTRAK_TLE_URL);
    let lastError: Error | null = null;
    for (let i = 0; i < sources.length; i++) {
      try {
        const result = await this.downloadAuto(sources[i]);
        if (result.count > 0) {
          return result;
        }
        lastError = new Error(`empty result: ${sources[i]}`);
      } catch (e) {
        lastError = e instanceof Error ? e : new Error(String(e));
      }
    }
    throw lastError !== null ? lastError : new Error('all sources failed');
  }

  /** 判断 URL 是否可下载的 HTTP(S) 地址。 */
  static isUsableUrl(url: string): boolean {
    const u = url.trim().toLowerCase();
    return u.startsWith('http://') || u.startsWith('https://');
  }

  /**
   * 自动识别格式下载：按行内含逗号判定 CSV（Celestrak FORMAT=csv），
   * 否则按 TLE 三行解析；解析为空时再试另一种，兼容用户自建源。
   */
  async downloadAuto(url: string): Promise<SatelliteDownloadResult> {
    const text = await this.fetchText(url);
    const looksCsv = SatelliteDownloader.looksLikeCsv(text);
    const first = looksCsv ? this.parser.parseCSVStream(text) : this.parser.parseTLEStream(text);
    if (first.length > 0) {
      return new SatelliteDownloadResult(first);
    }
    const second = looksCsv ? this.parser.parseTLEStream(text) : this.parser.parseCSVStream(text);
    return new SatelliteDownloadResult(second);
  }

  /** 采样前若干非空行，超过半数含逗号且含字母，则认为是 CSV。 */
  private static looksLikeCsv(text: string): boolean {
    const lines = text.split('\n');
    let checked = 0;
    let comma = 0;
    for (let i = 0; i < lines.length && checked < 5; i++) {
      const line = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      checked++;
      if (line.indexOf(',') >= 0) {
        comma++;
      }
    }
    return checked > 0 && comma * 2 > checked;
  }

  /** Parse a local TLE text snapshot (e.g. bundled in rawfile). */
  parseTLEText(text: string): SatelliteDownloadResult {
    return new SatelliteDownloadResult(this.parser.parseTLEStream(text));
  }

  /** Parse a local transponder JSON text snapshot. */
  parseTransponderText(text: string): TransponderDownloadResult {
    return new TransponderDownloadResult(this.parser.parseTransponderJSON(text));
  }

  /** Download transponder data from the domestic accelerated mirror (trans.json). */
  async downloadTransponders(url: string = CN_TRANSPONDER_URL): Promise<TransponderDownloadResult> {
    const text = await this.fetchText(url);
    const list = this.parser.parseTransponderJSON(text);
    return new TransponderDownloadResult(list);
  }

  /** Auto-detect format by extension/parameters: returns parsed satellites. */
  async download(autoFormat: boolean = true): Promise<SatelliteDownloadResult> {
    const csvText = await this.fetchText(CELESTRAK_CSV_URL);
    if (autoFormat && csvText.length > 0) {
      const list = this.parser.parseCSVStream(csvText);
      if (list.length > 0) {
        return new SatelliteDownloadResult(list);
      }
    }
    const tleList = this.parser.parseTLEStream(csvText);
    return new SatelliteDownloadResult(tleList);
  }

  private fetchText(url: string): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      const httpRequest = http.createHttp();
      httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 20000,
        readTimeout: 60000,
        header: { 'Accept': '*/*', 'User-Agent': 'Look4Sat-Harmony/1.0' }
      }, (err: BusinessError, data: http.HttpResponse) => {
        httpRequest.destroy();
        if (err) {
          reject(err);
          return;
        }
        const code = data.responseCode;
        if (code !== 200) {
          reject(new Error(`HTTP ${code}`));
          return;
        }
        const result: Object = data.result;
        resolve(this.resultToString(result));
      });
    });
  }

  private resultToString(result: Object): string {
    if (typeof result === 'string') {
      return result;
    }
    if (result instanceof ArrayBuffer) {
      return bytesToString(new Uint8Array(result));
    }
    return String(result);
  }
}