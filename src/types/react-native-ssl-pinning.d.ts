/**
 * Type declarations for react-native-ssl-public-key-pinning
 *
 * This library provides SSL certificate pinning for React Native.
 * https://github.com/frw/react-native-ssl-public-key-pinning
 */

declare module 'react-native-ssl-public-key-pinning' {
  export interface DomainConfig {
    /** Include subdomains in pinning */
    includeSubdomains?: boolean;
    /** Array of base64-encoded SPKI hashes (minimum 2 required for iOS/TrustKit) */
    publicKeyHashes: string[];
    /** Expiration date for the pins (ISO 8601 format) */
    expirationDate?: string;
  }

  export interface PinningConfig {
    [domain: string]: DomainConfig;
  }

  export interface SslPinningError {
    /** The hostname that failed pinning */
    serverHostname: string;
  }

  /**
   * Initialize SSL pinning with the given configuration
   * Must be called before making any network requests
   *
   * @param config - Domain to pin configuration mapping
   * @throws Error if configuration is invalid (e.g., less than 2 pins on iOS)
   */
  export function initializeSslPinning(config: PinningConfig): Promise<void>;

  /**
   * Check if SSL pinning is available on this platform
   *
   * @returns true if pinning is supported
   */
  export function isSslPinningAvailable(): boolean;

  /**
   * Add a listener for SSL pinning errors
   *
   * @param callback - Called when a pinning error occurs
   * @returns Subscription object with remove() method
   */
  export function addSslPinningErrorListener(
    callback: (error: SslPinningError) => void
  ): { remove: () => void };

  /**
   * Disable SSL pinning (for debugging only)
   * Warning: This completely disables certificate validation
   */
  export function disableSslPinning(): void;
}
