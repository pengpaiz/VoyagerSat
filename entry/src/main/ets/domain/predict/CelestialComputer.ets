/*
 * Look4Sat. Amateur radio satellite tracker and pass predictor.
 * Ported to HarmonyOS ArkTS from the Android Kotlin original (GPL-3.0).
 */

import {
  ASTRONOMICAL_UNIT, DEG2RAD, RAD2DEG, EARTH_RADIUS, FLAT_FACT, PI, TWO_PI
} from './Constants';
import { SatGeoPos } from './GeoPos';
import {
  solarPositionECI, eciToGeodetic
} from './OrbitalMath';
import {
  thetaGJD, mod2PI, millisToDaynum, daynumToMillis
} from '../../common/utils/MathUtils';
import { toRadians, toDegrees } from '../../common/utils/MathUtils';

export enum SatVisibility {
  VISIBLE = 0,
  DAYLIGHT = 1,
  ECLIPSED = 2
}

export class SatOrbitalMetadata {
  footprintDiameter: number;
  orbitNumber: number;
  betaAngle: number;
  orbitalPhase: number;

  constructor(footprintDiameter: number, orbitNumber: number, betaAngle: number, orbitalPhase: number) {
    this.footprintDiameter = footprintDiameter;
    this.orbitNumber = orbitNumber;
    this.betaAngle = betaAngle;
    this.orbitalPhase = orbitalPhase;
  }
}

export class SatRiseSetTimes {
  riseTimeMillis: number;
  setTimeMillis: number;

  constructor(riseTimeMillis: number, setTimeMillis: number) {
    this.riseTimeMillis = riseTimeMillis;
    this.setTimeMillis = setTimeMillis;
  }
}

export class SatSunPosition {
  azimuth: number;
  elevation: number;
  distance: number;
  rangeRate: number;
  latitude: number;
  longitude: number;
  rightAscension: number;
  declination: number;

  constructor(azimuth: number, elevation: number, distance: number, rangeRate: number, latitude: number,
              longitude: number, rightAscension: number, declination: number) {
    this.azimuth = azimuth;
    this.elevation = elevation;
    this.distance = distance;
    this.rangeRate = rangeRate;
    this.latitude = latitude;
    this.longitude = longitude;
    this.rightAscension = rightAscension;
    this.declination = declination;
  }
}

export class SatMoonPosition {
  azimuth: number;
  elevation: number;
  rightAscension: number;
  declination: number;
  gha: number;
  angularDiameter: number;
  radialVelocity: number;

  constructor(azimuth: number, elevation: number, rightAscension: number, declination: number, gha: number,
              angularDiameter: number, radialVelocity: number) {
    this.azimuth = azimuth;
    this.elevation = elevation;
    this.rightAscension = rightAscension;
    this.declination = declination;
    this.gha = gha;
    this.angularDiameter = angularDiameter;
    this.radialVelocity = radialVelocity;
  }
}

const MFACTOR_CMP = 7.292115E-5;

export class SatCelestialComputer {
  static getSunPosition(observer: SatGeoPos, timeMillis: number): SatSunPosition {
    const daynum = millisToDaynum(timeMillis);
    const julUtc = daynum + 2444238.5;
    const sunVec = solarPositionECI(julUtc);
    const zeroVel = [0.0, 0.0, 0.0];
    const obsGeo = SatCelestialComputer.observerGeodetic(observer);
    const obsSet = SatCelestialComputer.computeObsAngles(julUtc, sunVec, zeroVel, obsGeo);
    const latLon = eciToGeodetic(julUtc, sunVec);
    const raDec = SatCelestialComputer.calculateRADec(julUtc, sunVec, zeroVel, obsGeo);
    let lon = toDegrees(latLon[1]);
    if (lon > 180.0) {
      lon -= 360.0;
    }
    return new SatSunPosition(
      toDegrees(obsSet[0]),
      toDegrees(obsSet[1]),
      1.0 + ((obsSet[2] - ASTRONOMICAL_UNIT) / ASTRONOMICAL_UNIT),
      1000.0 * obsSet[3],
      toDegrees(latLon[0]),
      lon,
      toDegrees(raDec[0]),
      toDegrees(raDec[1])
    );
  }

  static getMoonPosition(observer: SatGeoPos, timeMillis: number): SatMoonPosition {
    const daynum = millisToDaynum(timeMillis);
    const jd = daynum + 2444238.5;
    let t = (jd - 2415020.0) / 36525.0;
    const t2 = t * t;
    const t3 = t2 * t;

    let l1 = 270.434164 + 481267.8831 * t - 0.001133 * t2 + 0.0000019 * t3;
    let mSun = 358.475833 + 35999.0498 * t - 0.00015 * t2 - 0.0000033 * t3;
    let m1 = 296.104608 + 477198.8491 * t + 0.009192 * t2 + 0.0000144 * t3;
    let d = 350.737486 + 445267.1142 * t - 0.001436 * t2 + 0.0000019 * t3;
    let ff = 11.250889 + 483202.0251 * t - 0.003211 * t2 - 0.0000003 * t3;
    const om = (259.183275 - 1934.142 * t + 0.002078 * t2 + 0.0000022 * t3) * DEG2RAD;

    const correction512 = Math.sin((51.2 + 20.2 * t) * DEG2RAD);
    const ss = 0.003964 * Math.sin((346.56 + 132.87 * t - 0.0091731 * t2) * DEG2RAD);
    l1 += 0.000233 * correction512 + ss + 0.001964 * Math.sin(om);
    mSun -= 0.001778 * correction512;
    m1 += 0.000817 * correction512 + ss + 0.002541 * Math.sin(om);
    d += 0.002011 * correction512 + ss + 0.001964 * Math.sin(om);
    ff += ss - 0.024691 * Math.sin(om) - 0.004328 * Math.sin(om + (275.05 - 2.3 * t) * DEG2RAD);

    const ex = 1.0 - 0.002495 * t - 0.00000752 * t2;
    l1 = SatCelestialComputer.primeAngle(l1);
    mSun = SatCelestialComputer.primeAngle(mSun);
    m1 = SatCelestialComputer.primeAngle(m1);
    d = SatCelestialComputer.primeAngle(d);
    ff = SatCelestialComputer.primeAngle(ff);

    const mR = mSun * DEG2RAD;
    const m1R = m1 * DEG2RAD;
    const dR = d * DEG2RAD;
    const ffR = ff * DEG2RAD;

    let l = l1 + 6.28875 * Math.sin(m1R) + 1.274018 * Math.sin(2 * dR - m1R) + 0.658309 * Math.sin(2 * dR);
    l += 0.213616 * Math.sin(2 * m1R) - ex * 0.185596 * Math.sin(mR) - 0.114336 * Math.sin(2 * ffR);
    l += 0.058793 * Math.sin(2 * dR - 2 * m1R) + ex * 0.057212 * Math.sin(2 * dR - mR - m1R) + 0.05332 * Math.sin(2 * dR + m1R);
    l += ex * 0.045874 * Math.sin(2 * dR - mR) + ex * 0.041024 * Math.sin(m1R - mR) - 0.034718 * Math.sin(dR);
    l -= ex * 0.030465 * Math.sin(mR + m1R) + 0.015326 * Math.sin(2 * dR - 2 * ffR) - 0.012528 * Math.sin(2 * ffR + m1R);
    l -= 0.01098 * Math.sin(2 * ffR - m1R) + 0.010674 * Math.sin(4 * dR - m1R) + 0.010034 * Math.sin(3 * m1R);
    l += 0.008548 * Math.sin(4 * dR - 2 * m1R) - ex * 0.00791 * Math.sin(mR - m1R + 2 * dR);
    l -= ex * 0.006783 * Math.sin(2 * dR + mR);
    l += 0.005162 * Math.sin(m1R - dR) + ex * 0.005 * Math.sin(mR + dR) + ex * 0.004049 * Math.sin(m1R - mR + 2 * dR);
    l += 0.003996 * Math.sin(2 * m1R + 2 * dR) + 0.003862 * Math.sin(4 * dR) + 0.003665 * Math.sin(2 * dR - 3 * m1R);
    l += ex * 0.002695 * Math.sin(2 * m1R - mR) + 0.002602 * Math.sin(m1R - 2 * ffR - 2 * dR);
    l += ex * 0.002396 * Math.sin(2 * dR - mR - 2 * m1R);
    l -= 0.002349 * Math.sin(m1R + dR) + ex * ex * 0.002249 * Math.sin(2 * dR - 2 * mR);
    l -= ex * 0.002125 * Math.sin(2 * m1R + mR);
    l -= ex * ex * 0.002079 * Math.sin(2 * mR) + ex * ex * 0.002059 * Math.sin(2 * dR - m1R - 2 * mR);
    l -= 0.001773 * Math.sin(m1R + 2 * dR - 2 * ffR);
    l += ex * 0.00122 * Math.sin(4 * dR - mR - m1R) - 0.00111 * Math.sin(2 * m1R + 2 * ffR) + 0.000892 * Math.sin(m1R - 3 * dR);
    l -= ex * 0.000811 * Math.sin(mR + m1R + 2 * dR) + ex * 0.000761 * Math.sin(4 * dR - mR - 2 * m1R);
    l += ex * ex * 0.000717 * Math.sin(m1R - 2 * mR);
    l += ex * ex * 0.000704 * Math.sin(m1R - 2 * mR - 2 * dR) + ex * 0.000693 * Math.sin(mR - 2 * m1R + 2 * dR);
    l += ex * 0.000598 * Math.sin(2 * dR - mR - 2 * ffR) + 0.00055 * Math.sin(m1R + 4 * dR);
    l += 0.000538 * Math.sin(4 * m1R) + ex * 0.000521 * Math.sin(4 * dR - mR) + 0.000486 * Math.sin(2 * m1R - dR);
    l -= 0.001595 * Math.sin(2 * ffR + 2 * dR);

    let b =
      5.128189 * Math.sin(ffR) + 0.280606 * Math.sin(m1R + ffR) + 0.277693 * Math.sin(m1R - ffR)
      + 0.173238 * Math.sin(2 * dR - ffR);
    b += 0.055413 * Math.sin(2 * dR + ffR - m1R) + 0.046272 * Math.sin(2 * dR - ffR - m1R) + 0.032573 * Math.sin(2 * dR + ffR);
    b += 0.017198 * Math.sin(2 * m1R + ffR) + 9.266999e-03 * Math.sin(2 * dR + m1R - ffR)
      + 0.008823 * Math.sin(2 * m1R - ffR);
    b += ex * 0.008247 * Math.sin(2 * dR - mR - ffR) + 0.004323 * Math.sin(2 * dR - ffR - 2 * m1R);
    b += 0.0042 * Math.sin(2 * dR + ffR + m1R);
    b += ex * 0.003372 * Math.sin(ffR - mR - 2 * dR) + ex * 0.002472 * Math.sin(2 * dR + ffR - mR - m1R);
    b += ex * 0.002222 * Math.sin(2 * dR + ffR - mR);
    b += 0.002072 * Math.sin(2 * dR - ffR - mR - m1R) + ex * 0.001877 * Math.sin(ffR - mR + m1R);
    b += 0.001828 * Math.sin(4 * dR - ffR - m1R);
    b -= ex * 0.001803 * Math.sin(ffR + mR) - 0.00175 * Math.sin(3 * ffR);
    b += ex * 0.00157 * Math.sin(m1R - mR - ffR) - 0.001487 * Math.sin(ffR + dR);
    b -= ex * 0.001481 * Math.sin(ffR + mR + m1R) + ex * 0.001417 * Math.sin(ffR - mR - m1R);
    b += ex * 0.00135 * Math.sin(ffR - mR) + 0.00133 * Math.sin(ffR - dR);
    b += 0.001106 * Math.sin(ffR + 3 * m1R) + 0.00102 * Math.sin(4 * dR - ffR) + 0.000833 * Math.sin(ffR + 4 * dR - m1R);
    b += 0.000781 * Math.sin(m1R - 3 * ffR) + 0.00067 * Math.sin(ffR + 4 * dR - 2 * m1R);
    b += 0.000606 * Math.sin(2 * dR - 3 * ffR);
    b += 0.000597 * Math.sin(2 * dR + 2 * m1R - ffR) + ex * 0.000492 * Math.sin(2 * dR + m1R - mR - ffR);
    b += 0.00045 * Math.sin(2 * m1R - ffR - 2 * dR);
    b += 0.000439 * Math.sin(3 * m1R - ffR) + 0.000423 * Math.sin(ffR + 2 * dR + 2 * m1R);
    b += 0.000422 * Math.sin(2 * dR - ffR - 3 * m1R);
    b -= ex * 0.000367 * Math.sin(mR + ffR + 2 * dR - m1R) - ex * 0.000353 * Math.sin(mR + ffR + 2 * dR);
    b += 0.000331 * Math.sin(ffR + 4 * dR);
    b += ex * 0.000317 * Math.sin(2 * dR + ffR - mR + m1R) + ex * ex * 0.000306 * Math.sin(2 * dR - 2 * mR - ffR);
    b -= 0.000283 * Math.sin(m1R + 3 * ffR);

    const w1 = 0.0004664 * Math.cos(om);
    const w2 = 0.0000754 * Math.cos(om + (275.05 - 2.3 * t) * DEG2RAD);
    const bt = b * (1.0 - w1 - w2);

    let p =
      0.950724 + 0.051818 * Math.cos(m1R) + 0.009531 * Math.cos(2 * dR - m1R) + 0.007843 * Math.cos(2 * dR)
      + 0.002824 * Math.cos(2 * m1R);
    p += 0.000857 * Math.cos(2 * dR + m1R) + ex * 0.000533 * Math.cos(2 * dR - mR)
      + ex * 0.000401 * Math.cos(2 * dR - mR - m1R);
    p += 0.000173 * Math.cos(3 * m1R) + 0.000167 * Math.cos(4 * dR - m1R) - ex * 0.000111 * Math.cos(mR);
    p += 0.000103 * Math.cos(4 * dR - 2 * m1R) - 0.000084 * Math.cos(2 * m1R - 2 * dR)
      - ex * 0.000083 * Math.cos(2 * dR + mR);
    p += 0.000079 * Math.cos(2 * dR + 2 * m1R);
    p += 0.000072 * Math.cos(4 * dR) + ex * 0.000064 * Math.cos(2 * dR - mR + m1R)
      - ex * 0.000063 * Math.cos(2 * dR + mR - m1R);
    p += ex * 0.000041 * Math.cos(mR + dR) + ex * 0.000035 * Math.cos(2 * m1R - mR) - 0.000033 * Math.cos(3 * m1R - 2 * dR);
    p -= 0.00003 * Math.cos(m1R + dR) - 0.000029 * Math.cos(2 * ffR - 2 * dR) - ex * 0.000029 * Math.cos(2 * m1R + mR);
    p += ex * ex * 0.000026 * Math.cos(2 * dR - 2 * mR) - 0.000023 * Math.cos(2 * ffR - 2 * dR + m1R);
    p += ex * 0.000019 * Math.cos(4 * dR - mR - m1R);

    const bRad = bt * DEG2RAD;
    const lm = l * DEG2RAD;
    const moonDx = 3.0 / (PI * p);

    const z = (jd - 2415020.5) / 365.2422;
    const ob = toRadians(23.452294 - (0.46845 * z + 5.9e-07 * z * z) / 3600.0);
    const dec = Math.asin(Math.sin(bRad) * Math.cos(ob) + Math.cos(bRad) * Math.sin(ob) * Math.sin(lm));
    let ra = Math.acos(Math.cos(bRad) * Math.cos(lm) / Math.cos(dec));
    if (lm > PI) {
      ra = TWO_PI - ra;
    }

    const n = observer.latitude * DEG2RAD;
    t = (jd - 2451545.0) / 36525.0;
    let teg = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + (0.000387933 * t - t * t / 38710000.0) * t;
    while (teg > 360.0) {
      teg -= 360.0;
    }
    const th = mod2PI((teg + observer.longitude) * DEG2RAD);
    const h = th - ra;
    const azVal = Math.atan2(Math.sin(h), Math.cos(h) * Math.sin(n) - Math.tan(dec) * Math.cos(n)) + PI;
    const el = Math.asin(Math.sin(n) * Math.sin(dec) + Math.cos(n) * Math.cos(dec) * Math.cos(h));

    const mm = SatCelestialComputer.fixAngle(1.319238 + daynum * 0.228027135);
    const radT2 = 0.10976;
    const radT1 = mm + radT2 * Math.sin(mm);
    let dv = 0.01255 * moonDx * moonDx * Math.sin(radT1) * (1.0 + radT2 * Math.cos(mm));
    dv *= 4449.0;
    const earthR = 6378.0;
    const moonDist = 384401.0;
    const radT3 = earthR * moonDist * (Math.cos(dec) * Math.cos(n) * Math.sin(h)) /
      Math.sqrt(moonDist * moonDist - moonDist * earthR * Math.sin(el));
    const moonDv = dv + radT3 * 0.0753125;

    const moonRa = ra / DEG2RAD;
    let moonGha = teg - moonRa;
    if (moonGha < 0.0) {
      moonGha += 360.0;
    }

    return new SatMoonPosition(
      azVal / DEG2RAD,
      el / DEG2RAD,
      moonRa,
      dec / DEG2RAD,
      moonGha,
      moonDx,
      moonDv
    );
  }

  static classifyVisibility(isEclipsed: boolean, sunElevationDeg: number, satElevationDeg: number): SatVisibility {
    if (isEclipsed) {
      return SatVisibility.ECLIPSED;
    }
    return (sunElevationDeg <= -12.0 && satElevationDeg >= 0.0) ? SatVisibility.VISIBLE : SatVisibility.DAYLIGHT;
  }

  static computeOrbitalMetadata(altitudeKm: number, meanMotion: number, bstar: number, meanAnomaly: number,
                                revNumAtEpoch: number, ageDays: number, phase: number,
                                satPosECI: number[], satVelECI: number[], sunPosECI: number[]): SatOrbitalMetadata {
    const footprint = 12756.33 * Math.acos(EARTH_RADIUS / (EARTH_RADIUS + altitudeKm));
    const xmnpda = 1.44E3;
    const orbitNum = Math.floor(
      (meanMotion * xmnpda / TWO_PI + ageDays * bstar) * ageDays + meanAnomaly / TWO_PI
    ) + revNumAtEpoch;
    const nx = satPosECI[1] * satVelECI[2] - satPosECI[2] * satVelECI[1];
    const ny = satPosECI[2] * satVelECI[0] - satPosECI[0] * satVelECI[2];
    const nz = satPosECI[0] * satVelECI[1] - satPosECI[1] * satVelECI[0];
    const nMag = Math.sqrt(nx * nx + ny * ny + nz * nz);
    const sMag = Math.sqrt(sunPosECI[0] * sunPosECI[0] + sunPosECI[1] * sunPosECI[1] + sunPosECI[2] * sunPosECI[2]);
    const dotNS = nx * sunPosECI[0] + ny * sunPosECI[1] + nz * sunPosECI[2];
    const betaAngle = (nMag > 0 && sMag > 0) ? (PI / 2.0 - Math.acos(dotNS / (nMag * sMag))) * RAD2DEG : 0.0;
    const orbitalPhase = 256.0 * (phase / TWO_PI);
    return new SatOrbitalMetadata(footprint, orbitNum, betaAngle, orbitalPhase);
  }

  static isGeostationary(meanMotion: number): boolean {
    return Math.abs(meanMotion - 1.0027) < 0.0002;
  }

  static hasDecayed(meanMotion: number, drag: number, epochDaynum: number, currentDaynum: number): boolean {
    return epochDaynum + ((16.666666 - meanMotion) / (10.0 * Math.abs(drag))) < currentDaynum;
  }

  static findSunRiseSet(observer: SatGeoPos, startMillis: number): SatRiseSetTimes {
    const threshold = 0.8333;
    let daynum = millisToDaynum(startMillis);
    let sunPos = SatCelestialComputer.getSunPosition(observer, daynumToMillis(daynum));

    if (sunPos.elevation > -threshold) {
      let guard = 0;
      while (sunPos.elevation > -threshold && guard < 500) {
        daynum += 0.008;
        sunPos = SatCelestialComputer.getSunPosition(observer, daynumToMillis(daynum));
        guard++;
      }
      guard = 0;
      while (sunPos.elevation > -12.0 && guard < 500) {
        daynum += 0.02;
        sunPos = SatCelestialComputer.getSunPosition(observer, daynumToMillis(daynum));
        guard++;
      }
    }

    let guard = 0;
    while (sunPos.elevation < -threshold && guard < 500) {
      daynum += 0.008;
      sunPos = SatCelestialComputer.getSunPosition(observer, daynumToMillis(daynum));
      guard++;
    }

    let sunrise = 0.0;
    guard = 0;
    while (sunrise === 0.0 && guard < 200) {
      const delta = sunPos.elevation + threshold;
      if (Math.abs(delta) < 0.01) {
        sunrise = daynum;
      } else {
        daynum -= 0.004 * delta;
        sunPos = SatCelestialComputer.getSunPosition(observer, daynumToMillis(daynum));
      }
      guard++;
    }
    if (sunrise === 0.0) {
      sunrise = daynum;
    }

    daynum = sunrise + 0.001;
    sunPos = SatCelestialComputer.getSunPosition(observer, daynumToMillis(daynum));
    guard = 0;
    while (sunPos.elevation > -threshold && guard < 500) {
      daynum += 0.008;
      sunPos = SatCelestialComputer.getSunPosition(observer, daynumToMillis(daynum));
      guard++;
    }

    let sunset = 0.0;
    guard = 0;
    while (sunset === 0.0 && guard < 200) {
      const delta = sunPos.elevation + threshold;
      if (Math.abs(delta) < 0.01) {
        sunset = daynum;
      } else {
        daynum += 0.004 * delta;
        sunPos = SatCelestialComputer.getSunPosition(observer, daynumToMillis(daynum));
      }
      guard++;
    }
    if (sunset === 0.0) {
      sunset = daynum;
    }

    return new SatRiseSetTimes(daynumToMillis(sunrise), daynumToMillis(sunset));
  }

  static findMoonRiseSet(observer: SatGeoPos, startMillis: number): SatRiseSetTimes {
    let daynum = millisToDaynum(startMillis);
    let moonPos = SatCelestialComputer.getMoonPosition(observer, daynumToMillis(daynum));

    let guard = 0;
    if (moonPos.elevation > 0) {
      while (moonPos.elevation > 0 && guard < 1000) {
        daynum += 0.004 * Math.sin(DEG2RAD * (moonPos.elevation + 0.5));
        moonPos = SatCelestialComputer.getMoonPosition(observer, daynumToMillis(daynum));
        guard++;
      }
      daynum += 0.4;
      moonPos = SatCelestialComputer.getMoonPosition(observer, daynumToMillis(daynum));
    }
    let moonrise = 0.0;
    guard = 0;
    while (moonrise === 0.0 && guard < 1000) {
      if (Math.abs(moonPos.elevation) < 0.03) {
        moonrise = daynum;
      } else {
        daynum -= 0.004 * moonPos.elevation;
        moonPos = SatCelestialComputer.getMoonPosition(observer, daynumToMillis(daynum));
      }
      guard++;
    }
    if (moonrise === 0.0) {
      moonrise = daynum;
    }

    daynum = moonrise;
    moonPos = SatCelestialComputer.getMoonPosition(observer, daynumToMillis(daynum));
    guard = 0;
    while (moonPos.elevation > -1 && guard < 1000) {
      daynum += 0.04 * Math.cos(DEG2RAD * (moonPos.elevation + 0.5));
      moonPos = SatCelestialComputer.getMoonPosition(observer, daynumToMillis(daynum));
      guard++;
    }
    let moonset = 0.0;
    guard = 0;
    while (moonset === 0.0 && guard < 1000) {
      if (Math.abs(moonPos.elevation) < 0.03) {
        moonset = daynum;
      } else {
        daynum += 0.004 * moonPos.elevation;
        moonPos = SatCelestialComputer.getMoonPosition(observer, daynumToMillis(daynum));
      }
      guard++;
    }
    if (moonset === 0.0) {
      moonset = daynum;
    }

    return new SatRiseSetTimes(daynumToMillis(moonrise), daynumToMillis(moonset));
  }

  static estimateVisualMagnitude(rangeKm: number, phaseAngleDeg: number, stdMag: number = 4.0): number {
    if (rangeKm <= 0) {
      return stdMag;
    }
    const halfPhaseRad = toRadians(phaseAngleDeg) / 2.0;
    const cosHalfPhase = Math.cos(halfPhaseRad);
    const phaseTerm = cosHalfPhase > 1e-6 ? -15.0 * Math.log10(cosHalfPhase) : 99.0;
    return stdMag + 5.0 * Math.log10(rangeKm / 1000.0) + phaseTerm;
  }

  static computePhaseAngle(satPosECI: number[], sunPosECI: number[], obsPosECI: number[]): number {
    const toSunX = sunPosECI[0] - satPosECI[0];
    const toSunY = sunPosECI[1] - satPosECI[1];
    const toSunZ = sunPosECI[2] - satPosECI[2];
    const toObsX = obsPosECI[0] - satPosECI[0];
    const toObsY = obsPosECI[1] - satPosECI[1];
    const toObsZ = obsPosECI[2] - satPosECI[2];
    const dot = toSunX * toObsX + toSunY * toObsY + toSunZ * toObsZ;
    const magSun = Math.sqrt(toSunX * toSunX + toSunY * toSunY + toSunZ * toSunZ);
    const magObs = Math.sqrt(toObsX * toObsX + toObsY * toObsY + toObsZ * toObsZ);
    if (magSun === 0.0 || magObs === 0.0) {
      return 90.0;
    }
    const cosAngle = Math.max(-1.0, Math.min(1.0, dot / (magSun * magObs)));
    return Math.acos(cosAngle) * RAD2DEG;
  }

  static dopplerShift(frequencyHz: number, rangeRateKmS: number): number {
    return frequencyHz * (299792.458 - rangeRateKmS) / 299792.458;
  }

  private static observerGeodetic(pos: SatGeoPos): number[] {
    return [pos.latitude * DEG2RAD, pos.longitude * DEG2RAD, pos.altitude / 1000.0];
  }

  private static calculateRADec(julUtc: number, targetPos: number[], targetVel: number[], obsGeo: number[]): number[] {
    const obsSet = SatCelestialComputer.computeObsAngles(julUtc, targetPos, targetVel, obsGeo);
    const az = obsSet[0];
    const el = obsSet[1];
    const phi = obsGeo[0];
    const theta = mod2PI(thetaGJD(julUtc) + obsGeo[1]);
    const sinTheta = Math.sin(theta);
    const cosTheta = Math.cos(theta);
    const sinPhi = Math.sin(phi);
    const cosPhi = Math.cos(phi);
    const lxh = -Math.cos(az) * Math.cos(el);
    const lyh = Math.sin(az) * Math.cos(el);
    const lzh = Math.sin(el);
    const sx = sinPhi * cosTheta;
    const ex2 = -sinTheta;
    const zx = cosTheta * cosPhi;
    const sy = sinPhi * sinTheta;
    const zy = sinTheta * cosPhi;
    const sz = -cosPhi;
    const lx = sx * lxh + ex2 * lyh + zx * lzh;
    const ly = sy * lxh + cosTheta * lyh + zy * lzh;
    const lz = sz * lxh + 0.0 * lyh + sinPhi * lzh;
    const dec = Math.asin(lz);
    const cosDelta = Math.sqrt(1.0 - lz * lz);
    const sinAlpha = ly / cosDelta;
    const cosAlpha = lx / cosDelta;
    const ra = mod2PI(Math.atan2(sinAlpha, cosAlpha));
    return [ra, dec];
  }

  private static computeObsAngles(julUtc: number, targetPos: number[], targetVel: number[],
                                   obsGeo: number[]): number[] {
    const theta = mod2PI(thetaGJD(julUtc) + obsGeo[1]);
    const c = 1.0 / Math.sqrt(1 + FLAT_FACT * (FLAT_FACT - 2) * Math.pow(Math.sin(obsGeo[0]), 2));
    const sq = Math.pow((1 - FLAT_FACT), 2) * c;
    const achcp = (EARTH_RADIUS * c + obsGeo[2]) * Math.cos(obsGeo[0]);
    const ox = achcp * Math.cos(theta);
    const oy = achcp * Math.sin(theta);
    const oz = (EARTH_RADIUS * sq + obsGeo[2]) * Math.sin(obsGeo[0]);
    const ovx = -MFACTOR_CMP * oy;
    const ovy = MFACTOR_CMP * ox;

    const rx = targetPos[0] - ox;
    const ry = targetPos[1] - oy;
    const rz = targetPos[2] - oz;
    const rMag = Math.sqrt(rx * rx + ry * ry + rz * rz);
    const rvx = targetVel[0] - ovx;
    const rvy = targetVel[1] - ovy;
    const rvz = targetVel[2];

    const sinLat = Math.sin(obsGeo[0]);
    const cosLat = Math.cos(obsGeo[0]);
    const sinTheta2 = Math.sin(theta);
    const cosTheta2 = Math.cos(theta);
    const topS = sinLat * cosTheta2 * rx + sinLat * sinTheta2 * ry - cosLat * rz;
    const topE = -sinTheta2 * rx + cosTheta2 * ry;
    const topZ = cosLat * cosTheta2 * rx + cosLat * sinTheta2 * ry + sinLat * rz;

    let azim = Math.atan(-topE / topS);
    if (topS > 0.0) {
      azim += PI;
    }
    if (azim < 0.0) {
      azim += TWO_PI;
    }
    const el = Math.asin(topZ / rMag);
    const rangeRate = (rx * rvx + ry * rvy + rz * rvz) / rMag;
    return [azim, el, rMag, rangeRate];
  }

  private static primeAngle(x: number): number {
    return x - 360.0 * Math.floor(x / 360.0);
  }

  private static fixAngle(x: number): number {
    let a = x;
    while (a > TWO_PI) {
      a -= TWO_PI;
    }
    return a;
  }
}