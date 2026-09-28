/*
 * Look4Sat. Amateur radio satellite tracker and pass predictor.
 * Ported to HarmonyOS ArkTS from the Android Kotlin original (GPL-3.0).
 */

import { EARTH_RADIUS, SPEED_OF_LIGHT, DEG2RAD, RAD2DEG } from './Constants';
import { SatGeoPos } from './GeoPos';

const GM_EARTH = 3.986004418E14;
const EARTH_RADIUS_M = 6.37E6;

export class SatOrbitalPos {
  azimuth: number;
  elevation: number;
  latitude: number;
  longitude: number;
  altitude: number;
  distance: number;
  distanceRate: number;
  theta: number;
  time: number;
  phase: number;
  eclipseDepth: number;
  eclipsed: boolean;
  aboveHorizon: boolean;

  constructor() {
    this.azimuth = 0.0;
    this.elevation = 0.0;
    this.latitude = 0.0;
    this.longitude = 0.0;
    this.altitude = 0.0;
    this.distance = 0.0;
    this.distanceRate = 0.0;
    this.theta = 0.0;
    this.time = 0;
    this.phase = 0.0;
    this.eclipseDepth = 0.0;
    this.eclipsed = false;
    this.aboveHorizon = false;
  }

  getDownlinkFreq(freq: number): number {
    return Math.trunc(freq * (SPEED_OF_LIGHT - this.distanceRate * 1000.0) / SPEED_OF_LIGHT);
  }

  getUplinkFreq(freq: number): number {
    return Math.trunc(freq * (SPEED_OF_LIGHT + this.distanceRate * 1000.0) / SPEED_OF_LIGHT);
  }

  getOrbitalVelocity(): number {
    const radius = EARTH_RADIUS_M + this.altitude * 1000.0;
    return Math.sqrt(GM_EARTH / radius) / 1000.0;
  }

  getRangeCircle(): SatGeoPos[] {
    const pointCount = 721;
    const rangeCirclePoints: SatGeoPos[] = [];
    const beta = Math.acos(EARTH_RADIUS / (EARTH_RADIUS + this.altitude));
    const sinLat = Math.sin(this.latitude);
    const cosLat = Math.cos(this.latitude);
    const cosBeta = Math.cos(beta);
    const sinBeta = Math.sin(beta);
    for (let azimuth = 0; azimuth <= 720; azimuth++) {
      const rads = azimuth * DEG2RAD;
      const lat = Math.asin(sinLat * cosBeta + cosLat * sinBeta * Math.cos(rads));
      const lon = this.longitude + Math.atan2(Math.sin(rads) * sinBeta * cosLat, cosBeta - sinLat * Math.sin(lat));
      rangeCirclePoints.push(new SatGeoPos(lat * RAD2DEG, lon * RAD2DEG));
    }
    return rangeCirclePoints;
  }
}