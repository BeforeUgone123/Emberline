declare module 'libfusion_terminal_driver.so' {
  const driver: {
    initialize(filesDir: string): void;
    startLocal(cols: number, rows: number): boolean;
    connectSsh(host: string, port: number, user: string, password: string, cols: number, rows: number): boolean;
    stop(): void;
    writeInput(data: string): void;
    drainOutput(): string;
    setOutputCallback(callback: ((data: string) => void) | null): void;
    resize(cols: number, rows: number): void;
  };

  export default driver;
}

