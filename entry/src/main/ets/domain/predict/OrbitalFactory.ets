/*
 * Look4Sat. Amateur radio satellite tracker and pass predictor.
 * Poll unionity: create the right SGP4/SDP4 propagator for a satellite.
 */

import { SatOrbitalData } from './OrbitalData';
import { SatOrbitalObject } from './OrbitalObject';
import { SatNearEarthObject } from './NearEarthObject';
import { SatDeepSpaceObject } from './DeepSpaceObject';

export function createOrbitalObject(data: SatOrbitalData): SatOrbitalObject {
  if (data.isDeepSpace) {
    return new SatDeepSpaceObject(data);
  }
  return new SatNearEarthObject(data);
}