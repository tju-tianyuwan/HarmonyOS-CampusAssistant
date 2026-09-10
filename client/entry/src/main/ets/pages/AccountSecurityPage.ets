import { AppTheme } from '../common/AppTheme';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';
import { UserInfo } from '../model/Models';
import { inputMethod } from '@kit.IMEKit';

interface IdentityRequest { account_type: string; email: string; school_name: string; student_number: string; }
interface ResetRequest extends IdentityRequest { code: string; new_password: string; }
interface PasswordRequest { current_password: string; new_password: string; }
interface EmailRequest { email: string; current_password: string; }
interface EmailConfirmation extends EmailRequest { code: string; }

@Component
export struct AccountSecurityPage {
  recovery: boolean = false;
  onClose: () => void = () => {};
  onPasswordChanged: () => void = () => {};
  @State school: boolean = false;
  @State binding: boolean = false;
  @State email: string = '';
  @State schoolName: string = '';
  @State number: string = '';
  @State currentPassword: string = '';
  @State password: string = '';
  @State confirmation: string = '';
  @State code: string = '';
  @State message: string = '';
  @State success: boolean = false;
  @State busy: boolean = false;
  @State cooldown: number = 0;
  private timer: number = -1;
  private active: boolean = true;

  aboutToAppear(): void { this.active = true; }
  aboutToDisappear(): void {
    this.active = false;
    AppStorage.setOrCreate<boolean>('accountInputFocused', false);
    if (this.timer >= 0) { clearInterval(this.timer); }
  }

  private focusInput(): void { AppStorage.setOrCreate<boolean>('accountInputFocused', true); }

  private async sendCode(): Promise<void> {
    if (this.busy || this.cooldown > 0) { return; }
    this.busy = true;
    try {
      if (this.recovery) {
        const body: IdentityRequest = { account_type: this.school ? 'school' : 'personal', email: this.email.trim(),
          school_name: this.schoolName.trim(), student_number: this.number.trim() };
        await Api.post('/auth/password-reset/code', body);
      } else {
        const body: EmailRequest = { email: this.email.trim(), current_password: this.currentPassword };
        await Api.post('/auth/recovery-email/code', body);
      }
      if (!this.active) { return; }
      this.message = this.recovery ? '若账号已绑定邮箱，验证码将发送到该邮箱' : '验证码已发送';
      this.cooldown = 60;
      this.timer = setInterval(() => {
        this.cooldown--;
        if (this.cooldown <= 0) { clearInterval(this.timer); this.timer = -1; }
      }, 1000);
    } catch (e) { if (this.active) { this.message = (e as Error).message; } }
    finally { this.busy = false; }
  }

  private async submit(): Promise<void> {
    if (this.busy) { return; }
    if (!this.binding && (this.password.length < 8 || this.password.length > 128 || this.password !== this.confirmation)) {
      this.message = '密码需为 8 至 128 位，两次输入必须一致'; return;
    }
    this.busy = true;
    this.message = '';
    inputMethod.getController().hideTextInput().catch(() => {});
    try {
      if (this.recovery) {
        const body: ResetRequest = { account_type: this.school ? 'school' : 'personal', email: this.email.trim(),
          school_name: this.schoolName.trim(), student_number: this.number.trim(), code: this.code, new_password: this.password };
        await Api.post('/auth/password-reset', body);
        this.message = '密码已重置，请使用新密码登录';
      } else if (this.binding) {
        const body: EmailConfirmation = { email: this.email.trim(), current_password: this.currentPassword, code: this.code };
        const user = JSON.parse(await Api.post('/auth/recovery-email', body)) as UserInfo;
        if (!this.active) { return; }
        GlobalState.user = user;
        this.message = '找回邮箱已绑定';
      } else {
        const body: PasswordRequest = { current_password: this.currentPassword, new_password: this.password };
        await Api.post('/auth/password', body);
        this.message = '密码已修改，所有设备需重新登录';
        this.onPasswordChanged();
      }
      this.currentPassword = '';
      this.password = '';
      this.confirmation = '';
      this.code = '';
      this.success = true;
    } catch (e) { if (this.active) { this.message = (e as Error).message; } }
    finally { this.busy = false; }
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Button('返回').fontColor(AppTheme.PRIMARY_DEEP).backgroundColor(Color.Transparent)
            .enabled(!this.busy).onClick(() => { this.onClose(); })
          Text(this.recovery ? '找回密码' : '账号安全').fontSize(22).fontWeight(FontWeight.Bold).layoutWeight(1)
        }.width('100%')
        if (!this.recovery && GlobalState.user?.account_type === 'school') {
          Row({ space: 8 }) {
            Button('修改密码').layoutWeight(1).backgroundColor(this.binding ? AppTheme.PRIMARY_LIGHT : AppTheme.PRIMARY)
              .fontColor(this.binding ? AppTheme.PRIMARY_DEEP : '#FFFFFF')
              .onClick(() => { this.binding = false; this.success = false; this.message = ''; })
            Button('找回邮箱').layoutWeight(1).backgroundColor(this.binding ? AppTheme.PRIMARY : AppTheme.PRIMARY_LIGHT)
              .fontColor(this.binding ? '#FFFFFF' : AppTheme.PRIMARY_DEEP)
              .onClick(() => { this.binding = true; this.success = false; this.message = ''; })
          }.enabled(!this.busy)
        }
        if (!this.success) {
          if (this.recovery) {
            Row({ space: 8 }) {
              Radio({ value: 'personal', group: 'recovery' }).checked(!this.school).onChange((v: boolean) => { if (v) { this.school = false; } })
              Text('个人账号').fontSize(14)
              Radio({ value: 'school', group: 'recovery' }).checked(this.school).onChange((v: boolean) => { if (v) { this.school = true; } })
              Text('学校账号').fontSize(14)
            }.enabled(!this.busy)
            if (this.school) {
              TextInput({ placeholder: '学校名称', text: this.schoolName }).onFocus(() => { this.focusInput(); }).onChange((v: string) => { this.schoolName = v; })
              TextInput({ placeholder: '学号或工号', text: this.number }).onFocus(() => { this.focusInput(); }).onChange((v: string) => { this.number = v; })
            } else {
              TextInput({ placeholder: '注册邮箱', text: this.email }).type(InputType.Email).onFocus(() => { this.focusInput(); }).onChange((v: string) => { this.email = v; })
            }
          } else {
            TextInput({ placeholder: '当前密码', text: this.currentPassword }).type(InputType.Password)
              .onChange((v: string) => { this.currentPassword = v; })
              .onFocus(() => { this.focusInput(); })
          }
          if (this.binding) {
            Text(GlobalState.user?.email ? `当前邮箱：${GlobalState.user?.email}` : '尚未绑定找回邮箱').fontSize(13).width('100%')
            TextInput({ placeholder: '新的找回邮箱', text: this.email }).type(InputType.Email).onFocus(() => { this.focusInput(); }).onChange((v: string) => { this.email = v; })
          }
          if (this.recovery || this.binding) {
            Row({ space: 8 }) {
              TextInput({ placeholder: '邮箱验证码', text: this.code }).layoutWeight(1).maxLength(6).type(InputType.Number)
                .onFocus(() => { this.focusInput(); })
                .onChange((v: string) => { this.code = v; })
              Button(this.cooldown > 0 ? `${this.cooldown} 秒` : '发送验证码').enabled(!this.busy && this.cooldown === 0)
                .backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).onClick(() => { this.sendCode(); })
            }
          }
          if (!this.binding) {
            TextInput({ placeholder: '新密码（8 至 128 位）', text: this.password }).type(InputType.Password).maxLength(128)
              .onChange((v: string) => { this.password = v; })
              .onFocus(() => { this.focusInput(); })
            TextInput({ placeholder: '确认新密码', text: this.confirmation }).type(InputType.Password).maxLength(128)
              .onChange((v: string) => { this.confirmation = v; })
              .onFocus(() => { this.focusInput(); })
          }
          Button(this.busy ? '正在提交' : this.binding ? '绑定邮箱' : this.recovery ? '重置密码' : '修改密码')
            .width('100%').backgroundColor(AppTheme.PRIMARY).enabled(!this.busy)
            .onClick(() => { this.submit(); })
        }
        if (this.message !== '') {
          Text(this.message).fontSize(14).fontColor(this.success ? AppTheme.PRIMARY_DEEP : AppTheme.TEXT_SECONDARY).width('100%')
        }
        if (this.success && this.recovery) {
          Button('返回登录').width('100%').backgroundColor(AppTheme.PRIMARY).onClick(() => { this.onClose(); })
        }
      }.width('100%').constraintSize({ maxWidth: 460 }).padding(24)
    }.width('100%').height('100%').align(Alignment.Top).backgroundColor(AppTheme.BG_PAGE)
  }
}
