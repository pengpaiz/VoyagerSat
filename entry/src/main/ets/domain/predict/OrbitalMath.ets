/*
 * Look4Sat. Amateur radio satellite tracker and pass predictor.
 * Ported to HarmonyOS ArkTS from the Android Kotlin original (GPL-3.0).
 */

import {
  ASTRONOMICAL_UNIT, DEG2RAD, EARTH_RADIUS, FLAT_FACT, SEC_PER_DAY, PI_2, TWO_PI
} from './Constants';
import {
  modulus, mod2PI, mod360, thetaGJD, deltaET
} from '../../common/utils/MathUtils';

/**
 * Compute the Sun's ECI position vector at [julUtc] (Julian UTC).
 * Returns [x, y, z, magnitude] in km. Based on PREDICT v2.2.5 Calculate_Solar_Position().
 */
export function solarPositionECI(julUtc: number): number[] {
  const mjd = julUtc - 2415020.0;
  const year = 1900 + mjd / 365.25;
  const t = (mjd + deltaET(year) / SEC_PER_DAY) / 36525.0;
  const mDeg = mod360(358.47583 + mod360(35999.04975 * t) - (0.000150 + 0.0000033 * t) * t * t);
  const m = mDeg * DEG2RAD;
  const lDeg = mod360(279.69668 + mod360(36000.76892 * t) + 0.0003025 * t * t);
  const l = lDeg * DEG2RAD;
  const e = 0.01675104 - (0.0000418 + 0.000000126 * t) * t;
  const cDeg = (1.919460 - (0.004789 + 0.000014 * t) * t) * Math.sin(m) +
    (0.020094 - 0.000100 * t) * Math.sin(2 * m) + 0.000293 * Math.sin(3 * m);
  const c = cDeg * DEG2RAD;
  const oDeg = mod360(259.18 - 1934.142 * t);
  const o = oDeg * DEG2RAD;
  const lsa = mod2PI(l + c - (0.00569 - 0.00479 * Math.sin(o)) * DEG2RAD);
  const nu = mod2PI(m + c);
  let r = 1.0000002 * (1.0 - e * e) / (1.0 + e * Math.cos(nu));
  const epsDeg = 23.452294 - (0.0130125 + (0.00000164 - 0.000000503 * t) * t) * t + 0.00256 * Math.cos(o);
  const eps = epsDeg * DEG2RAD;
  r *= ASTRONOMICAL_UNIT;
  return [r * Math.cos(lsa), r * Math.sin(lsa) * Math.cos(eps), r * Math.sin(lsa) * Math.sin(eps), r];
}

/**
 * Convert ECI position [eciPos] = [x, y, z] (km) to geodetic [lat_rad, lon_rad, alt_km].
 * Based on PREDICT v2.2.5 Calculate_LatLonAlt().
 */
export function eciToGeodetic(julUtc: number, eciPos: number[]): number[] {
  const thetaPos = Math.atan2(eciPos[1], eciPos[0]);
  const lon = mod2PI(thetaPos - thetaGJD(julUtc));
  const r = Math.sqrt(eciPos[0] * eciPos[0] + eciPos[1] * eciPos[1]);
  const e2 = FLAT_FACT * (2.0 - FLAT_FACT);
  let lat = Math.atan2(eciPos[2], r);
  let phi: number;
  let c: number;
  let i = 0;
  let latOut = lat;
  do {
    phi = latOut;
    c = 1.0 / Math.sqrt(1.0 - e2 * Math.sin(phi) * Math.sin(phi));
    latOut = Math.atan2(eciPos[2] + EARTH_RADIUS * c * e2 * Math.sin(phi), r);
    i++;
  } while (i < 11 && Math.abs(latOut - phi) >= 1E-10);
  const alt = r / Math.cos(latOut) - EARTH_RADIUS * c;
  if (latOut > PI_2) {
    latOut -= TWO_PI;
  }
  return [latOut, lon, alt];
}