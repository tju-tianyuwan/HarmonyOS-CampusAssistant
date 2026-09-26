import { TouchMotion } from '../common/TouchMotion';
import { AppTheme } from '../common/AppTheme';
import { AuthResponse } from '../model/Models';
import { Api } from '../service/Api';
import { AccountSecurityPage } from './AccountSecurityPage';

interface Credentials {
  account_type: string;
  role: string;
  email: string;
  school_name: string;
  student_number: string;
  password: string;
  name: string;
  code: string;
}
interface EmailRequest { email: string; }

@Component
export struct AuthPage {
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  onAuthenticated: (response: AuthResponse) => void = () => {};
  @State registering: boolean = false;
  @State recovering: boolean = false;
  @State school: boolean = false;
  @State teacher: boolean = false;
  @State name: string = '';
  @State email: string = '';
  @State schoolName: string = '';
  @State studentNumber: string = '';
  @State password: string = '';
  @State confirmation: string = '';
  @State code: string = '';
  @State message: string = '';
  @State busy: boolean = false;
  @State sending: boolean = false;
  @State cooldown: number = 0;
  private timer: number = -1;

  aboutToDisappear(): void {
    if (this.timer >= 0) { clearInterval(this.timer); }
  }

  private async sendCode(): Promise<void> {
    if (this.sending || this.cooldown > 0) { return; }
    this.sending = true;
    try {
      const body: EmailRequest = { email: this.email.trim() };
      await Api.post('/auth/verification-code', body);
      this.message = '验证码已发送';
      this.cooldown = 60;
      this.timer = setInterval(() => {
        this.cooldown--;
        if (this.cooldown <= 0) { clearInterval(this.timer); this.timer = -1; }
      }, 1000);
    } catch (e) { this.message = (e as Error).message; }
    finally { this.sending = false; }
  }

  private async submit(): Promise<void> {
    if (this.busy) { return; }
    if (this.registering && this.password !== this.confirmation) { this.message = '两次密码不一致'; return; }
    const body: Credentials = { account_type: this.school ? 'school' : 'personal',
      role: this.teacher ? 'teacher' : 'student', email: this.email.trim(),
      school_name: this.schoolName.trim(), student_number: this.studentNumber.trim(), password: this.password,
      name: this.name.trim(), code: this.code.trim() };
    this.busy = true;
    this.message = '';
    try {
      const response = JSON.parse(await Api.post(this.registering ? '/auth/register' : '/auth/login', body)) as AuthResponse;
      this.password = '';
      this.confirmation = '';
      this.onAuthenticated(response);
    } catch (e) { this.message = (e as Error).message; }
    finally { this.busy = false; }
  }

  build() {
    if (this.recovering) {
      AccountSecurityPage({ recovery: true, onClose: () => { this.recovering = false; } })
    } else {
    Scroll() {
      Column({ space: 16 }) {
        Row({ space: 12 }) {
          Image($r('app.media.app_icon')).width(52).height(52).borderRadius(12)
          Text('智慧伴学').fontSize(28).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
        }.width('100%')
        Row({ space: 12 }) {
          Button('登录').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).backgroundColor(this.registering ? AppTheme.BG_PAGE : AppTheme.PRIMARY)
            .fontColor(this.registering ? AppTheme.TEXT_SECONDARY : '#FFFFFF')
            .onClick(() => { this.registering = false; this.message = ''; })
          Button('注册').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).backgroundColor(this.registering ? AppTheme.PRIMARY : AppTheme.BG_PAGE)
            .fontColor(this.registering ? '#FFFFFF' : AppTheme.TEXT_SECONDARY)
            .onClick(() => { this.registering = true; this.message = ''; })
        }.width('100%').enabled(!this.busy)
        Row({ space: 16 }) {
          Radio({ value: 'personal', group: 'account' }).checked(!this.school).onChange((v: boolean) => { if (v) { this.school = false; } })
          Text('个人账号').fontSize(14)
          Radio({ value: 'school', group: 'account' }).checked(this.school).onChange((v: boolean) => { if (v) { this.school = true; } })
          Text('学校账号').fontSize(14)
        }.enabled(!this.busy)
        if (this.registering) {
          Row({ space: 16 }) {
            Radio({ value: 'student', group: 'role' }).checked(!this.teacher)
              .onChange((v: boolean) => { if (v) { this.teacher = false; } })
            Text('学生').fontSize(14)
            Radio({ value: 'teacher', group: 'role' }).checked(this.teacher)
              .onChange((v: boolean) => { if (v) { this.teacher = true; } })
            Text('教师').fontSize(14)
          }.width('100%').enabled(!this.busy)
          TextInput({ placeholder: '姓名', text: this.name }).height(44).onChange((v: string) => { this.name = v; })
        }
        if (this.school) {
          TextInput({ placeholder: '学校名称', text: this.schoolName }).height(44).onChange((v: string) => { this.schoolName = v; })
          TextInput({ placeholder: this.registering ? (this.teacher ? '教师工号' : '学生学号') : '学号或工号',
            text: this.studentNumber })
            .height(44).onChange((v: string) => { this.studentNumber = v; })
        } else {
          TextInput({ placeholder: '邮箱', text: this.email }).height(44).type(InputType.Email).onChange((v: string) => { this.email = v; })
        }
        TextInput({ placeholder: '密码', text: this.password }).height(44).type(InputType.Password).onChange((v: string) => { this.password = v; })
        if (this.registering) {
          TextInput({ placeholder: '确认密码', text: this.confirmation }).height(44).type(InputType.Password).onChange((v: string) => { this.confirmation = v; })
          if (!this.school) {
            Row({ space: 8 }) {
              TextInput({ placeholder: '验证码', text: this.code }).height(44).layoutWeight(1).maxLength(6).onChange((v: string) => { this.code = v; })
              Button(this.cooldown > 0 ? `${this.cooldown} 秒` : '发送验证码').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).height(44)
                .backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP)
                .enabled(!this.sending && this.cooldown === 0).onClick(() => { this.sendCode(); })
            }
          }
        }
        if (this.message !== '') { Text(this.message).fontSize(13).fontColor(AppTheme.DANGER).width('100%') }
        Button(this.busy ? '正在提交' : this.registering ? '注册并登录' : '登录').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width('100%').height(46)
          .backgroundColor(AppTheme.PRIMARY).enabled(!this.busy).onClick(() => { this.submit(); })
        if (!this.registering) {
          Button('忘记密码').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(Color.Transparent).fontColor(AppTheme.PRIMARY_DEEP)
            .enabled(!this.busy).onClick(() => { this.recovering = true; })
        }
      }.width('100%').constraintSize({ maxWidth: 460 }).padding(28)
    }.width('100%').height('100%').align(Alignment.Top).backgroundColor('#F1FBF8')
    }
  }
}
