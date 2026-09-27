/*
 * Look4Sat. Amateur radio satellite tracker and pass predictor.
 * Ported to HarmonyOS ArkTS from the Android Kotlin original (GPL-3.0).
 */

import { SatGeoPos } from '../predict/GeoPos';
import { SatOrbitalPos } from '../predict/OrbitalPos';
import { toRadians, toDegrees } from '../../common/utils/MathUtils';

const AVG_EARTH_RADIUS_KM = 6371.009;
const MIN_LATITUDE = -85.05112877980658;
const MAX_LATITUDE = 85.05112877980658;
const MIN_LONGITUDE = -180.0;
const MAX_LONGITUDE = 180.0;

export function greatCircleDistanceKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const lat1R = toRadians(lat1);
  const lat2R = toRadians(lat2);
  const lon1R = toRadians(lon1);
  const lon2R = toRadians(lon2);
  return Math.acos(
    Math.sin(lat1R) * Math.sin(lat2R) + Math.cos(lat1R) * Math.cos(lat2R) * Math.cos(lon2R - lon1R)
  ) * AVG_EARTH_RADIUS_KM;
}

export function bearingDeg(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const lat1R = toRadians(lat1);
  const lat2R = toRadians(lat2);
  const dLon = toRadians(lon2 - lon1);
  const y = Math.sin(dLon) * Math.cos(lat2R);
  const x = Math.cos(lat1R) * Math.sin(lat2R) - Math.sin(lat1R) * Math.cos(lat2R) * Math.cos(dLon);
  return (toDegrees(Math.atan2(y, x)) + 360) % 360;
}

export function clipLat(latitude: number): number {
  return clipValue(latitude, MIN_LATITUDE, MAX_LATITUDE);
}

export function clipLon(longitude: number): number {
  let result = longitude;
  while (result < MIN_LONGITUDE) {
    result += 360.0;
  }
  while (result > MAX_LONGITUDE) {
    result -= 360.0;
  }
  return clipValue(result, MIN_LONGITUDE, MAX_LONGITUDE);
}

export function toMapGeoPos(pos: SatOrbitalPos): SatGeoPos {
  return new SatGeoPos(
    clipLat(toDegrees(pos.latitude)),
    clipLon(toDegrees(pos.longitude))
  );
}

function clipValue(currentValue: number, minValue: number, maxValue: number): number {
  return Math.min(Math.max(currentValue, minValue), maxValue);
}