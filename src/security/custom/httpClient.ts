/**
 * HTTP Client for Security Level: custom
 *
 * Native SPKI certificate pinning with dual-layer validation:
 *   1. Native DataSyncManager.ensureConfigSync() — HttpsURLConnection-based SPKI check
 *   2. ConfigInterceptor — OkHttp interceptor validates every request at network level
 *
 * JS-side timing check adds a third detection layer.
 * Session is permanently compromised if any check fails (sticky flag).
 */

import DataSyncManager from '../../native/DataSyncManager';
import {
  SSL_PIN_DOMAIN,
  SSL_PIN_HASH_1,
} from '@env';

export interface SecureFetchResponse {
  ok: boolean;
  status: number;
  headers: Record<string, string>;
  url: string;
  json: () => Promise<any>;
  text: () => Promise<string>;
}

// Sticky flag — once true, all requests are blocked for app lifecycle
let sessionCompromised = false;

const headersToObject = (headers: Headers): Record<string, string> => {
  const result: Record<string, string> = {};
  headers.forEach((value, key) => {
    result[key] = value;
  });
  return result;
};

/**
 * Perform a fetch request with native SPKI certificate pinning.
 * Calls ensureConfigSync() before every fetch to validate the certificate
 * via a separate TLS stack (HttpsURLConnection), then lets OkHttp's
 * ConfigInterceptor validate again at the network level.
 */
export const secureFetch = async (
  url: string,
  options: RequestInit = {},
): Promise<SecureFetchResponse> => {
  if (sessionCompromised) {
    throw new Error('DataSync: Session integrity lost');
  }

  const domain = SSL_PIN_DOMAIN || 'vulnbank.org';
  const pinHash = SSL_PIN_HASH_1 || '';

  // Native SPKI validation with JS-side timing check
  if (DataSyncManager) {
    const start = Date.now();
    try {
      await DataSyncManager.ensureConfigSync(domain, pinHash);
    } catch (error: any) {
      sessionCompromised = true;
      throw new Error(`DataSync: Configuration sync failed - ${error?.message || error}`);
    }
    const elapsed = Date.now() - start;

    // JS timing layer: real TLS handshake + SPKI extraction takes > 30ms
    if (elapsed < 30) {
      sessionCompromised = true;
      throw new Error('DataSync: Session integrity lost');
    }
  }

  try {
    const response = await fetch(url, options);

    return {
      ok: response.ok,
      status: response.status,
      headers: headersToObject(response.headers),
      url: response.url,
      json: () => response.json(),
      text: () => response.text(),
    };
  } catch (error: any) {
    // If the ConfigInterceptor rejects, it surfaces here
    if (error?.message?.includes('DataSync')) {
      sessionCompromised = true;
    }
    throw error;
  }
};

/**
 * Check if a fetch error is a security/pinning error.
 */
export const isSecurityError = (error: any): boolean => {
  const errorMessage = error?.message || String(error);
  return (
    errorMessage.includes('DataSync') ||
    errorMessage.includes('Configuration mismatch') ||
    errorMessage.includes('Session integrity') ||
    errorMessage.includes('SSL') ||
    errorMessage.includes('certificate') ||
    errorMessage.includes('CERT') ||
    errorMessage.includes('Trust anchor') ||
    sessionCompromised
  );
};
