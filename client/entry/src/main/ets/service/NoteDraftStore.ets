import { fileIo } from '@kit.CoreFileKit';

export interface NoteDraft { title: string; content: string; }

export class NoteDraftStore {
  private directory: string;
  constructor(filesDir: string, server: string, userId: number) {
    this.directory = `${filesDir}/notes_${encodeURIComponent(server)}_${userId}`;
    if (!fileIo.accessSync(this.directory)) { fileIo.mkdirSync(this.directory); }
  }
  save(id: number, draft: NoteDraft): void {
    const temporary = `${this.directory}/${id}.tmp`;
    const file = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(file.fd, JSON.stringify(draft)); fileIo.fsyncSync(file.fd); }
    finally { fileIo.closeSync(file); }
    fileIo.renameSync(temporary, `${this.directory}/${id}.json`);
  }
  load(id: number): NoteDraft | null {
    const path = `${this.directory}/${id}.json`;
    if (!fileIo.accessSync(path)) { return null; }
    return JSON.parse(fileIo.readTextSync(path)) as NoteDraft;
  }
  remove(id: number): void {
    const path = `${this.directory}/${id}.json`;
    if (fileIo.accessSync(path)) { fileIo.unlinkSync(path); }
  }
}
