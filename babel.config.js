// Load merged environment file (.env.build)
// The Makefile creates .env.build by merging .env (shared) + .env.{level} (flags)
//
// Build process:
//   1. Makefile runs: cat .env .env.{level} > .env.build
//   2. Babel loads .env.build with all settings merged
//
// This allows shared settings (API_BASE, SSL pins) to be maintained in one place
// while level-specific flags remain in separate files.

const securityLevel = process.env.SECURITY_LEVEL || 'library';
const validLevels = ['l00', 'none', 'library', 'proxy-bypass', 'custom', 'frida-resistant'];

// Validate security level
if (!validLevels.includes(securityLevel)) {
  console.warn(
    `Warning: Invalid SECURITY_LEVEL "${securityLevel}". ` +
    `Valid options: ${validLevels.join(', ')}. Defaulting to "library".`
  );
}

console.log(`Building with security level: ${securityLevel}`);

module.exports = {
  presets: ['module:@react-native/babel-preset'],
  plugins: [
    ['module:react-native-dotenv', {
      moduleName: '@env',
      path: '.env.build',
      allowUndefined: true,
    }],
  ],
};
