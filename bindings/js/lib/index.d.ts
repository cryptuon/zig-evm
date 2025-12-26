/**
 * Zig EVM TypeScript Definitions
 */

export interface EVMResult {
  success: boolean;
  errorCode: number;
  errorName: string;
  gasUsed: bigint;
  gasRemaining: bigint;
  returnData: Buffer;
  reverted: boolean;
}

export interface Log {
  address: Buffer;
  topics: Buffer[];
  data: Buffer;
}

export declare const EVMError: {
  OK: 0;
  OUT_OF_GAS: 1;
  STACK_UNDERFLOW: 2;
  STACK_OVERFLOW: 3;
  INVALID_OPCODE: 4;
  INVALID_JUMP: 5;
  REVERT: 6;
  STATIC_CALL_VIOLATION: 7;
  OUT_OF_MEMORY: 8;
  CALL_DEPTH_EXCEEDED: 9;
  INSUFFICIENT_BALANCE: 10;
  INVALID_ARGUMENT: 11;
  UNKNOWN_ERROR: 255;
};

export declare const ErrorNames: Record<number, string>;

export declare class EVM {
  constructor();

  /** Destroy the EVM instance */
  destroy(): void;

  /** Reset EVM state for new execution */
  reset(): void;

  // Configuration
  setGasLimit(gasLimit: number | bigint): void;
  setBlockNumber(number: number | bigint): void;
  setTimestamp(timestamp: number | bigint): void;
  setChainId(chainId: number | bigint): void;
  setCoinbase(address: string | Buffer): void;
  setAddress(address: string | Buffer): void;
  setCaller(address: string | Buffer): void;
  setOrigin(address: string | Buffer): void;
  setValue(value: number | bigint | string | Buffer): void;

  // Account management
  setBalance(address: string | Buffer, balance: number | bigint | string | Buffer): void;
  setCode(address: string | Buffer, code: Buffer | string): void;
  setStorage(address: string | Buffer, key: number | bigint | string | Buffer, value: number | bigint | string | Buffer): void;
  getStorage(address: string | Buffer, key: number | bigint | string | Buffer): Buffer;

  // Execution
  execute(code: Buffer | string, calldata?: Buffer | string): EVMResult;

  // Results
  readonly gasUsed: bigint;
  readonly gasRemaining: bigint;
  getReturnData(): Buffer;

  // Logs
  getLogs(): Log[];

  // Debugging
  readonly stackDepth: number;
  stackPeek(index?: number): Buffer | null;
  readonly memorySize: number;
  memoryRead(offset: number, length: number): Buffer;
}

export declare function version(): string;
