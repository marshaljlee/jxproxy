/**
 * Eligibility check for remote managed settings.
 *
 * jxproxy: always returns false to prevent phone-home to api.anthropic.com.
 * The reset function is kept for compatibility with callers.
 */

import { resetSyncCache as resetLeafCache } from './syncCacheState.js'

export function resetSyncCache(): void {
  cached = undefined
  resetLeafCache()
}

/**
 * Check if the current user is eligible for remote managed settings
 *
 * jxproxy always returns false — remote managed settings are disabled
 * to prevent phone-home calls to api.anthropic.com.
 */
export function isRemoteManagedSettingsEligible(): boolean {
  return false
}
