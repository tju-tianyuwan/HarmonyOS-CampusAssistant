import { AiAgentInfo } from '../model/Models';
import { LocalAgentTurn, LocalAskResult, LocalBackend } from './LocalBackend';

export interface StreamCallbacks {
  onSources: (sources: string[]) => void;
  onWarning: (msg: string) => void;
  onDelta: (delta: string) => void;
  onAgent?: (agent: AiAgentInfo) => void;
  onAgentDone?: (agentId: string) => void;
  onDone: () => void;
  onError: (msg: string) => void;
}

/**
 * Competition build API facade.
 *
 * All requests are dispatched to the embedded ArkTS backend. The public API is
 * intentionally identical to the network build so existing pages need no
 * changes and the entire application runs from one HAP.
 */
export class Api {
  static BASE_URL: string = 'embedded://local/api/v1';

  static async get(path: string): Promise<string> {
    return LocalBackend.get(path);
  }

  static async post(path: string, body?: object): Promise<string> {
    return LocalBackend.post(path, body);
  }

  static async postLong(path: string, body: object): Promise<string> {
    return LocalBackend.post(path, body);
  }

  static async put(path: string, body: object): Promise<string> {
    return LocalBackend.put(path, body);
  }

  static async remove(path: string): Promise<string> {
    return LocalBackend.remove(path);
  }

  static async uploadChunk(sessionId: number, seq: number, data: ArrayBuffer): Promise<string> {
    return LocalBackend.uploadChunk(sessionId, seq, data);
  }

  static streamAsk(chatSessionId: number, question: string, contextNote: string,
    cb: StreamCallbacks, mode: string = 'single'): void {
    let result: LocalAskResult;
    try {
      result = LocalBackend.ask(chatSessionId, question, contextNote, mode);
    } catch (e) {
      cb.onError((e as Error).message);
      return;
    }

    cb.onSources(result.sources);
    if (result.warning !== '') {
      cb.onWarning(result.warning);
    }
    Api.emitTurn(result.turns, 0, cb);
  }

  private static emitTurn(turns: LocalAgentTurn[], turnIndex: number, cb: StreamCallbacks): void {
    if (turnIndex >= turns.length) {
      cb.onDone();
      return;
    }
    const turn: LocalAgentTurn = turns[turnIndex];
    if (turn.agent !== null && cb.onAgent !== undefined) {
      cb.onAgent(turn.agent);
    }
    Api.emitText(turn, 0, (): void => {
      if (turn.agent !== null && cb.onAgentDone !== undefined) {
        cb.onAgentDone(turn.agent.id);
      }
      setTimeout((): void => {
        Api.emitTurn(turns, turnIndex + 1, cb);
      }, 90);
    }, cb);
  }

  private static emitText(turn: LocalAgentTurn, offset: number, done: () => void,
    cb: StreamCallbacks): void {
    if (offset >= turn.content.length) {
      done();
      return;
    }
    const end: number = Math.min(turn.content.length, offset + 8);
    cb.onDelta(turn.content.substring(offset, end));
    setTimeout((): void => {
      Api.emitText(turn, end, done, cb);
    }, 18);
  }
}
