import { fileIo } from '@kit.CoreFileKit';

export interface RecordingDraft { sessionId: number; title: string; nextSeq: number; }

export class RecordingStore {
  private directory: string;
  constructor(filesDir: string, server: string, userId: number, courseId: number) {
    this.directory = `${filesDir}/recording_${encodeURIComponent(server)}_${userId}_${courseId}`;
    if (!fileIo.accessSync(this.directory)) { fileIo.mkdirSync(this.directory); }
  }

  private write(path: string, data: string | ArrayBuffer): void {
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, data);
      fileIo.fsyncSync(file.fd);
    } finally { fileIo.closeSync(file); }
  }

  save(draft: RecordingDraft): void {
    this.write(`${this.directory}/state.tmp`, JSON.stringify(draft));
    fileIo.renameSync(`${this.directory}/state.tmp`, `${this.directory}/state.json`);
  }

  load(): RecordingDraft | null {
    const path = `${this.directory}/state.json`;
    if (!fileIo.accessSync(path)) { return null; }
    return JSON.parse(fileIo.readTextSync(path)) as RecordingDraft;
  }

  append(seq: number, data: ArrayBuffer): void {
    this.write(`${this.directory}/${seq}.tmp`, data);
    fileIo.renameSync(`${this.directory}/${seq}.tmp`, `${this.directory}/${seq}.pcm`);
  }

  pending(): number[] {
    return fileIo.listFileSync(this.directory).filter((name: string) => /^\d+\.pcm$/.test(name))
      .map((name: string) => Number(name.split('.')[0])).sort((a: number, b: number) => a - b);
  }

  read(seq: number): ArrayBuffer {
    const file = fileIo.openSync(`${this.directory}/${seq}.pcm`, fileIo.OpenMode.READ_ONLY);
    try {
      const data = new ArrayBuffer(fileIo.statSync(file.fd).size);
      if (fileIo.readSync(file.fd, data) !== data.byteLength) { throw new Error('录音缓存读取不完整'); }
      return data;
    } finally { fileIo.closeSync(file); }
  }

  remove(seq: number): void { fileIo.unlinkSync(`${this.directory}/${seq}.pcm`); }
  finish(): void { fileIo.unlinkSync(`${this.directory}/state.json`); }
}
