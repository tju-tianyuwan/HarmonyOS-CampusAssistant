import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

export interface SavedSession { server: string; token: string; }

export class SessionStore {
  private static queue: Promise<void> = Promise.resolve();

  private static attributes(): asset.AssetMap {
    const values: asset.AssetMap = new Map();
    values.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto('campus-session-v1'));
    return values;
  }

  static save(server: string, token: string): Promise<void> {
    const session: SavedSession = { server: server, token: token };
    const task = SessionStore.queue.catch(() => {}).then(async () => {
      const values = SessionStore.attributes();
      values.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(JSON.stringify(session)));
      values.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
      values.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
      await asset.add(values);
    });
    SessionStore.queue = task;
    return task;
  }

  static async load(): Promise<SavedSession | null> {
    await SessionStore.queue.catch(() => {});
    const values = SessionStore.attributes();
    values.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results = await asset.query(values);
      if (results.length === 0) { return null; }
      const bytes = results[0].get(asset.Tag.SECRET) as Uint8Array;
      const session = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(bytes)) as SavedSession;
      if (typeof session.server !== 'string' || typeof session.token !== 'string') { return null; }
      return session;
    } catch (e) { return null; }
  }
}
