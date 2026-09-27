/*
 * Look4Sat. Device GPS location helper using Location Kit.
 */

import { geoLocationManager } from '@kit.LocationKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SatGeoPos } from '../domain/predict/GeoPos';

const LOCATION_PERMISSIONS: Permissions[] = [
  'ohos.permission.APPROXIMATELY_LOCATION',
  'ohos.permission.LOCATION'
];

export class Locator {
  /**
   * Request location permission if missing, then fetch current position.
   * Returns null on failure / denial.
   */
  static async getCurrentPosition(context: common.Context): Promise<SatGeoPos | null> {
    if (!await Locator.ensurePermission(context)) {
      return null;
    }
    return await Locator.fetch();
  }

  private static async ensurePermission(context: common.Context): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager();
    try {
      const req = await atManager.requestPermissionsFromUser(context, LOCATION_PERMISSIONS);
      for (let i = 0; i < req.authResults.length; i++) {
        if (req.authResults[i] === abilityAccessCtrl.GrantStatus.PERMISSION_DENIED) {
          return false;
        }
      }
      return req.authResults.length > 0;
    } catch (e) {
      return false;
    }
  }

  private static fetch(): Promise<SatGeoPos | null> {
    return new Promise<SatGeoPos | null>((resolve) => {
      const request: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
        scenario: geoLocationManager.LocationRequestScenario.TRAJECTORY_TRACKING,
        maxAccuracy: 0,
        timeoutMs: 10000
      };
      try {
        geoLocationManager.getCurrentLocation(request, (err: BusinessError, loc: geoLocationManager.Location) => {
          if (err) {
            resolve(null);
            return;
          }
          resolve(new SatGeoPos(loc.latitude, loc.longitude, loc.altitude ?? 0, 'gps'));
        });
      } catch (e) {
        resolve(null);
      }
    });
  }
}