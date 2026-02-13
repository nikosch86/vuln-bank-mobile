const {getDefaultConfig, mergeConfig} = require('@react-native/metro-config');
const path = require('path');
const fs = require('fs');

// Security level from environment variable (default: library to match babel.config.js)
const securityLevel = process.env.SECURITY_LEVEL || 'library';

console.log(`[Metro] Building with SECURITY_LEVEL=${securityLevel}`);

// Map security levels to their implementation directories
const securityLevelMap = {
  'l00': 'none',              // Same as none, but trusts user-installed CAs
  'none': 'none',
  'library': 'library',
  'proxy-bypass': 'library',  // Uses library base + additional modules
  'custom': 'custom',
  'frida-resistant': 'frida-resistant',
};

// Get the security implementation directory for current level
const securityImpl = securityLevelMap[securityLevel] || 'none';
const projectRoot = __dirname;

// Exclusion patterns - higher levels excluded from lower level builds
const getExclusions = (level) => {
  const exclusions = [];

  const levelExclusions = {
    'l00': ['library', 'proxy-bypass', 'custom', 'frida-resistant'],
    'none': ['library', 'proxy-bypass', 'custom', 'frida-resistant'],
    'library': ['proxy-bypass', 'custom', 'frida-resistant'],
    'proxy-bypass': ['custom', 'frida-resistant'],
    'custom': ['frida-resistant'],
    'frida-resistant': [],
  };

  const toExclude = levelExclusions[level] || [];

  for (const excludeLevel of toExclude) {
    exclusions.push(
      new RegExp(`${projectRoot.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}/src/security/${excludeLevel}/.*`)
    );
  }

  return exclusions;
};

/**
 * Metro configuration
 */
const config = {
  resolver: {
    blockList: getExclusions(securityLevel),

    resolveRequest: (context, moduleName, platform) => {
      // Check if this is a security module import
      // Matches: ../security/httpClient, ./security/httpClient, etc.
      if (moduleName.includes('/security/httpClient') && !moduleName.includes(`/security/${securityImpl}/`)) {
        // Redirect to the level-specific implementation
        const newModuleName = moduleName.replace('/security/httpClient', `/security/${securityImpl}/httpClient`);

        console.log(`[Metro] Redirecting ${moduleName} -> ${newModuleName}`);

        return context.resolveRequest(context, newModuleName, platform);
      }

      // Default resolution
      return context.resolveRequest(context, moduleName, platform);
    },
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
