declare module '@env' {
  // API Configuration
  export const API_BASE: string;

  // Security Level: 'library' | 'proxy-bypass' | 'custom' | 'frida-resistant'
  export const SECURITY_LEVEL: string;

  // Feature Flags
  export const ENABLE_SSL_PINNING: string;
  export const ENABLE_PROXY_DETECTION: string;
  export const USE_CUSTOM_SSL_MODULE: string;
  export const ENABLE_ANTI_TAMPERING: string;
  export const ENABLE_ROOT_DETECTION: string;

  // SSL Pinning Configuration
  export const SSL_PIN_DOMAIN: string;
  export const SSL_PIN_HASH_1: string;
  export const SSL_PIN_HASH_2: string;
}
