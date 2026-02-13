/**
 * HTTP Client for Security Level: library
 *
 * Uses react-native-ssl-public-key-pinning for certificate pinning.
 * Pinning is initialized once at app startup, then standard fetch is used.
 * Bypassable with standard Frida scripts.
 */

import {
  initializeSslPinning,
  isSslPinningAvailable,
  addSslPinningErrorListener,
} from 'react-native-ssl-public-key-pinning';
import {
  SSL_PIN_DOMAIN,
  SSL_PIN_HASH_1,
  SSL_PIN_HASH_2,
} from '@env';

export interface SecureFetchResponse {
  ok: boolean;
  status: number;
  headers: Record<string, string>;
  url: string;
  json: () => Promise<any>;
  text: () => Promise<string>;
}

// Track initialization state
let pinningInitialized = false;
let pinningError: Error | null = null;

/**
 * Convert Headers object to plain object safely (React Native compatibility)
 */
const headersToObject = (headers: Headers): Record<string, string> => {
  const result: Record<string, string> = {};
  headers.forEach((value, key) => {
    result[key] = value;
  });
  return result;
};

/**
 * Get SPKI pin hashes from environment
 * Note: TrustKit (iOS) requires at least 2 pins.
 * Both pins can be identical on Android — the library accepts duplicates.
 */
const getSSLPins = (): string[] => {
  const pins: string[] = [];

  if (SSL_PIN_HASH_1) {
    pins.push(SSL_PIN_HASH_1);
  }

  if (SSL_PIN_HASH_2) {
    pins.push(SSL_PIN_HASH_2);
  }

  return pins;
};

/**
 * Initialize SSL pinning (call once at app startup)
 */
export const initializePinning = async (): Promise<void> => {
  if (pinningInitialized) {
    return;
  }

  const pins = getSSLPins();
  const domain = SSL_PIN_DOMAIN || 'vulnbank.org';

  if (pins.length < 2) {
    console.warn(
      '[Security:library] SSL pinning requires at least 2 pins (TrustKit requirement). ' +
      'Run ./scripts/update-pins.sh to generate pins.'
    );
    pinningInitialized = true;
    return;
  }

  // Check if pinning is available on this platform
  if (!isSslPinningAvailable()) {
    console.warn('[Security:library] SSL pinning not available on this platform');
    pinningInitialized = true;
    return;
  }

  try {
    console.log(`[Security:library] Initializing SSL pinning for ${domain}`);

    // Set up error listener
    addSslPinningErrorListener((error) => {
      console.error('[Security:library] SSL pinning error:', error.serverHostname);
      pinningError = new Error(`Certificate pinning failed for ${error.serverHostname}`);
    });

    // Initialize pinning
    await initializeSslPinning({
      [domain]: {
        includeSubdomains: true,
        publicKeyHashes: pins,
      },
    });

    console.log('[Security:library] SSL pinning initialized successfully');
    pinningInitialized = true;
  } catch (error: any) {
    console.error('[Security:library] Failed to initialize SSL pinning:', error?.message || error);
    pinningError = error;
    pinningInitialized = true;
  }
};

/**
 * Perform a fetch request with SSL certificate pinning
 * Note: Pinning is applied automatically by the library after initialization
 */
export const secureFetch = async (
  url: string,
  options: RequestInit = {}
): Promise<SecureFetchResponse> => {
  // Ensure pinning is initialized
  if (!pinningInitialized) {
    await initializePinning();
  }

  console.log('[Security:library] Fetching:', url, 'method:', options.method || 'GET');

  try {
    // Standard fetch - pinning is applied automatically by the library
    const response = await fetch(url, options);
    console.log('[Security:library] Response status:', response.status);

    return {
      ok: response.ok,
      status: response.status,
      headers: headersToObject(response.headers),
      url: response.url,
      json: () => response.json(),
      text: () => response.text(),
    };
  } catch (error: any) {
    console.error('[Security:library] Fetch error:', error?.message || error);
    throw error;
  }
};

/**
 * Check if a fetch error is a security/pinning error
 */
export const isSecurityError = (error: any): boolean => {
  const errorMessage = error?.message || String(error);
  return (
    errorMessage.includes('Certificate pinning') ||
    errorMessage.includes('SSL') ||
    errorMessage.includes('certificate') ||
    errorMessage.includes('CERT') ||
    errorMessage.includes('Trust anchor') ||
    errorMessage.includes('pin') ||
    pinningError !== null
  );
};
