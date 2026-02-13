/**
 * HTTP Client for Security Level: none
 *
 * Uses standard fetch without any SSL pinning.
 * This is the baseline - fully vulnerable to MITM attacks.
 */

export interface SecureFetchResponse {
  ok: boolean;
  status: number;
  headers: Record<string, string>;
  url: string;
  json: () => Promise<any>;
  text: () => Promise<string>;
}

/**
 * Convert Headers object to plain object safely (React Native compatibility)
 */
const headersToObject = (headers: Headers): Record<string, string> => {
  const result: Record<string, string> = {};
  // forEach is more widely supported than entries() in React Native
  headers.forEach((value, key) => {
    result[key] = value;
  });
  return result;
};

/**
 * Perform a fetch request (no SSL pinning)
 */
export const secureFetch = async (
  url: string,
  options: RequestInit = {}
): Promise<SecureFetchResponse> => {
  console.log('[Security:none] Fetching:', url, 'method:', options.method || 'GET');

  try {
    const response = await fetch(url, options);
    console.log('[Security:none] Response status:', response.status);

    return {
      ok: response.ok,
      status: response.status,
      headers: headersToObject(response.headers),
      url: response.url,
      json: () => response.json(),
      text: () => response.text(),
    };
  } catch (error: any) {
    console.error('[Security:none] Fetch error:', error?.message || error);
    throw error;
  }
};

/**
 * Check if a fetch error is a security/pinning error
 * For 'none' level, this always returns false
 */
export const isSecurityError = (_error: any): boolean => {
  return false;
};
