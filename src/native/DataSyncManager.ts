import {NativeModules} from 'react-native';

interface DataSyncManagerInterface {
  ensureConfigSync(domain: string, pinHash: string): Promise<boolean>;
  validateCertificate(domain: string): Promise<boolean>;
  checkSSLPinning(): Promise<boolean>;
  verifyCertificateChain(): Promise<boolean>;
  getConnectionMetrics(): Promise<{
    validationCount: number;
    lastTimestamp: number;
    sessionIntegrity: boolean;
  }>;
}

const DataSyncManager: DataSyncManagerInterface | undefined =
  NativeModules.DataSyncManager;

export default DataSyncManager;
