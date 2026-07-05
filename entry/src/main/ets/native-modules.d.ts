declare module 'libfusion_terminal_driver.so' {
  const driver: {
    createSession(): number;
    destroySession(sessionId: number): void;
    initialize(sessionId: number, filesDir: string): void;
    startLocal(sessionId: number, cols: number, rows: number): boolean;
    connectSsh(sessionId: number, host: string, port: number, user: string, password: string,
      cols: number, rows: number): boolean;
    connectSshAsync(sessionId: number, host: string, port: number, user: string, password: string,
      cols: number, rows: number): Promise<boolean>;
    stop(sessionId: number): void;
    writeInput(sessionId: number, data: string): void;
    drainOutput(sessionId: number): string;
    setOutputCallback(sessionId: number, callback: ((data: string) => void) | null): void;
    setDirectOutputTarget(sessionId: number, surfaceId: string): void;
    resize(sessionId: number, cols: number, rows: number): void;
    sshUploadFile(host: string, port: number, user: string, password: string,
      localPath: string, remotePath: string): Promise<string>;
  };

  export default driver;
}
