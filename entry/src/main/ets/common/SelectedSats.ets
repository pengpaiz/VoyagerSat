/*
 * Look4Sat. Shared selected-satellites state across bottom tabs.
 * Held in AppStorage so tab1 (satellites) and tab2 (passes) stay in sync.
 */

import { ISS_CATNUM } from './SatelliteApp';

const CATS_KEY = 'selected_cats';
const VERSION_KEY = 'selected_version';
const SEEDED_KEY = 'selected_seeded';

export class SelectedSats {
  static init(forceDefault: boolean = false): void {
    PersistentStorage.persistProp(CATS_KEY, new Array<number>());
    PersistentStorage.persistProp(VERSION_KEY, 0);
    PersistentStorage.persistProp(SEEDED_KEY, false);
    if (forceDefault) {
      AppStorage.setOrCreate<number[]>(CATS_KEY, [ISS_CATNUM]);
      AppStorage.setOrCreate<number>(VERSION_KEY, 1);
      AppStorage.setOrCreate<boolean>(SEEDED_KEY, true);
      return;
    }
    const seeded = AppStorage.get<boolean>(SEEDED_KEY) ?? false;
    if (!seeded) {
      AppStorage.setOrCreate<boolean>(SEEDED_KEY, true);
      AppStorage.setOrCreate<number[]>(CATS_KEY, [ISS_CATNUM]);
      AppStorage.setOrCreate<number>(VERSION_KEY, 1);
    }
  }

  static getCats(): number[] {
    const cats = AppStorage.get<number[]>(CATS_KEY);
    return cats === undefined ? [] : cats;
  }

  static isSelected(catnum: number): boolean {
    const cats = SelectedSats.getCats();
    return cats.indexOf(catnum) >= 0;
  }

  static toggle(catnum: number): void {
    const cats = SelectedSats.getCats();
    const idx = cats.indexOf(catnum);
    if (idx >= 0) {
      cats.splice(idx, 1);
    } else {
      cats.push(catnum);
    }
    // store a fresh copy so AppStorage / @StorageLink detect the change
    AppStorage.setOrCreate<number[]>(CATS_KEY, Array.from(cats));
    SelectedSats.bumpVersion();
  }

  static clear(): void {
    AppStorage.setOrCreate<number[]>(CATS_KEY, []);
    SelectedSats.bumpVersion();
  }

  static bumpVersion(): void {
    const v = AppStorage.get<number>(VERSION_KEY) ?? 0;
    AppStorage.setOrCreate<number>(VERSION_KEY, v + 1);
  }

  static getVersion(): number {
    return AppStorage.get<number>(VERSION_KEY) ?? 0;
  }
}