// Determine which env file to use based on SECURITY_LEVEL
// Usage: SECURITY_LEVEL=frida-resistant npx react-native start
const securityLevel = process.env.SECURITY_LEVEL || 'library';
const validLevels = ['none', 'library', 'proxy-bypass', 'custom', 'frida-resistant'];

// Validate security level
if (!validLevels.includes(securityLevel)) {
  console.warn(
    `Warning: Invalid SECURITY_LEVEL "${securityLevel}". ` +
    `Valid options: ${validLevels.join(', ')}. Defaulting to "library".`
  );
}

// Select env file - fall back to .env.library if level-specific doesn't exist
const envFile = validLevels.includes(securityLevel)
  ? `.env.${securityLevel}`
  : '.env.library';

console.log(`Building with security level: ${securityLevel} (${envFile})`);

module.exports = {
  presets: ['module:@react-native/babel-preset'],
  plugins: [
    ['module:react-native-dotenv', {
      moduleName: '@env',
      path: envFile,
      allowUndefined: true,
    }],
  ],
};
