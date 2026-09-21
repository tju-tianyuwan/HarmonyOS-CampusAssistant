import { audio } from '@kit.AudioKit';

export async function closeRecordingCapture(capturer: audio.AudioCapturer, stopFirst: boolean): Promise<void> {
  if (stopFirst) {
    try {
      await capturer.stop();
    } catch (e) {
      // A failed stop may leave the native stream unusable; release must still run.
      console.warn(`RecordingCapture stop failed: ${(e as Error).message}`);
    }
  }
  try {
    await capturer.release();
  } catch (e) {
    throw new Error('麦克风暂时无法关闭，请再次点击结束；已采集的录音会保留');
  }
}
