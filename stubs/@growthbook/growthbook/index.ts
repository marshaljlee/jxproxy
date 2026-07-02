/**
 * Stub for @growthbook/growthbook
 *
 * The real package is tree-shaken away by Bun's bundler because:
 *   1. All code paths using GrowthBook class are behind dead conditions
 *      (isGrowthBookEnabled() always returns false; USER_TYPE === 'ant'
 *       is never true when compiled with process.env.USER_TYPE="external")
 *   2. The real package has "sideEffects": false, which permits elimination
 *
 * This stub prevents Bun from dropping the import entirely while being
 * minimal enough that the bundled footprint is near-zero. At runtime the
 * stub's GrowthBook class is never instantiated, so null/empty methods
 * are safe.
 */

export class GrowthBook {
  constructor(_options?: any) {
    // Never actually invoked in jxproxy — all paths are dead code.
  }

  getPayload(): any {
    return null;
  }

  setPayload(_payload: any): Promise<void> {
    return Promise.resolve();
  }

  getFeatures(): any {
    return {};
  }

  getExperiments(): any[] {
    return [];
  }

  getFeatureValue(_key: string, _fallback: any): any {
    return _fallback;
  }

  isOn(_key: string): boolean {
    return false;
  }

  isOff(_key: string): boolean {
    return true;
  }

  destroy(): void {}

  refreshFeatures(): Promise<void> {
    return Promise.resolve();
  }
}

export default GrowthBook;
