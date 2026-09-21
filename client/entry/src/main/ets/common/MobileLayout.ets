import { deviceInfo } from '@kit.BasicServicesKit';
import { GlobalState } from '../service/GlobalState';

export class MobileLayout {
  static phone(): boolean {
    return deviceInfo.deviceType === 'phone';
  }

  static studentPhone(): boolean {
    return deviceInfo.deviceType === 'phone' && !GlobalState.isTeacher();
  }
}
