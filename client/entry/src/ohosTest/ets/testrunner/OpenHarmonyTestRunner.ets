import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';
import { Api } from '../../../main/ets/service/Api';
import { RealtimeRecording } from '../../../main/ets/service/RealtimeRecording';
import { RecordingStore } from '../../../main/ets/service/RecordingStore';
import { TranscriptSegment } from '../../../main/ets/model/Models';

/** Device integration tests against server/tests/realtime_device_server.py only. */
export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void {}

  private assert(condition: boolean, message: string): void {
    if (!condition) { throw new Error(message); }
  }

  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const originalUrl = Api.BASE_URL;
    const originalToken = Api.token;
    let active: RealtimeRecording | null = null;
    try {
      Api.BASE_URL = 'http://10.0.2.2:8012/api/v1';
      Api.setAccessToken('realtime-device-test-token');
      interface SessionResult { id: number; }
      interface SessionRequest { class_course_id: number; creator_id: number; title: string; }
      const body: SessionRequest = { class_course_id: 1, creator_id: 1, title: 'Tablet realtime integration' };
      const session = JSON.parse(await Api.post('/sessions', body)) as SessionResult;
      const store = new RecordingStore(delegator.getAppContext().cacheDir, Api.BASE_URL, 1, session.id);
      store.save({ sessionId: session.id, title: body.title, nextSeq: 1, realtime: true });
      const first = new Uint8Array(6400);
      const second = new Uint8Array(3200);
      first.fill(1); second.fill(2);
      store.appendRealtime(0, first.buffer as ArrayBuffer);
      store.appendRealtime(0, second.buffer as ArrayBuffer);
      this.assert(store.read(0).byteLength === 9600, 'PCM append length');
      this.assert(new Uint8Array(store.readFrame(0, 6400))[0] === 2, 'PCM append offset');
      this.assert(store.load()?.realtime === true, 'Persisted realtime draft');
      await delegator.print('PASS device PCM append, frame offsets and draft recovery\n');

      let partial = '';
      active = new RealtimeRecording((text: string) => { partial = text; });
      await active.open(session.id, 0);
      await active.send(store.readFrame(0, 0));
      await RealtimeRecording.delay(600);
      this.assert(partial.indexOf('模拟字幕') >= 0, 'Interim text before END');
      active.close(); active = null;
      await RealtimeRecording.delay(300);
      const before = JSON.parse(await Api.get(`/sessions/${session.id}/transcript`)) as TranscriptSegment[];
      this.assert(before.length === 0 && store.pending().length === 1, 'Disconnect retains unconfirmed audio');
      await delegator.print('PASS real device WebSocket interim result and interrupted-window retention\n');

      active = new RealtimeRecording((text: string) => { partial = text; });
      await active.open(session.id, 0);
      await active.send(store.readFrame(0, 0));
      await active.send(store.readFrame(0, 6400));
      const saved = await active.finish(); active.close(); active = null;
      this.assert(saved.end_ms === 300 && saved.text.indexOf('测试') >= 0, 'Final result and sample-based timestamp');
      active = new RealtimeRecording(() => {});
      await active.open(session.id, 0);
      this.assert(active.committed()?.id === saved.id, 'Duplicate commit acknowledged');
      active.close(); active = null;
      store.remove(0); store.finish();
      await delegator.print('PASS replay, final save, duplicate ACK and cache cleanup\n');

      active = new RealtimeRecording(() => {});
      await active.open(session.id, 1);
      await active.send(new ArrayBuffer(3200));
      const resumed = await active.finish(); active.close(); active = null;
      this.assert(resumed.start_ms === 300 && resumed.end_ms === 400, 'Pause/resume timeline');
      await Api.post(`/sessions/${session.id}/finish`);
      const all = JSON.parse(await Api.get(`/sessions/${session.id}/transcript`)) as TranscriptSegment[];
      this.assert(all.length === 2, 'Saved transcript count');
      await delegator.print('PASS pause/resume timestamp and final session persistence\n');
      await delegator.finishTest('PASS 4 realtime device integration groups (simulated SIS, actual device network/storage)', 0);
    } catch (e) {
      await delegator.finishTest('FAIL realtime device integration: ' + (e as Error).message, 1);
    } finally {
      active?.close();
      Api.BASE_URL = originalUrl;
      Api.setAccessToken(originalToken);
    }
  }
}
