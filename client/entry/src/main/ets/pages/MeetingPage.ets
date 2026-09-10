import { AppTheme } from '../common/AppTheme';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';
import { picker, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

interface Room { id: number; name: string; creator_id: number; status: string; joined: boolean; enabled: boolean; participant_limit: number; minutes: string; }
interface Message { id: number; sender_name: string; role: string; content: string; }
interface Member { id: number; name: string; }
interface ManagedMember extends Member { role: string; joined: boolean; removed: boolean; }
interface MemberRequest { user_id: number; }
interface Detail { room: Room; members: Member[]; messages: Message[]; cursor: number; }
interface CreateRoomRequest { class_course_id: number; name: string; participant_limit: number; }
interface MessageRequest { content: string; immediate: boolean; }
interface SettingsRequest { participant_limit: number; enabled: boolean; }

@Component
export struct MeetingPage {
  @State rooms: Room[] = [];
  @State room: Room | null = null;
  @State messages: Message[] = [];
  @State members: Member[] = [];
  @State title: string = '';
  @State input: string = '';
  @State error: string = '';
  @State busy: boolean = false;
  @State immediate: boolean = false;
  @State minutes: boolean = false;
  @State settings: boolean = false;
  @State capacity: string = '20';
  @State meetingEnabled: boolean = true;
  @State compact: boolean = false;
  @State managingMembers: boolean = false;
  @State people: ManagedMember[] = [];
  private timer: number = -1;
  private cursor: number = 0;
  private generation: number = 0;
  private polling: boolean = false;
  private active: boolean = true;
  private courseId: number = GlobalState.courseId();
  aboutToAppear(): void { this.active = true; this.loadRooms(); this.timer = setInterval(() => { this.poll(); }, 3000); }
  aboutToDisappear(): void { this.active = false; this.generation++; clearInterval(this.timer); }

  private async loadRooms(): Promise<void> {
    try {
      const rooms = JSON.parse(await Api.get(`/meetings?class_course_id=${this.courseId}`)) as Room[];
      if (this.active) { this.rooms = rooms; }
    } catch (e) { this.error = (e as Error).message; }
  }

  private async selectRoom(room: Room): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      await Api.post(`/meetings/${room.id}/join`);
      this.generation++;
      this.room = room;
      this.messages = [];
      this.cursor = 0;
      this.capacity = `${room.participant_limit}`;
      this.meetingEnabled = room.enabled;
      this.settings = false;
      this.managingMembers = false;
      await this.poll();
    } catch (e) { this.error = (e as Error).message; }
    finally { this.busy = false; }
  }

  private async poll(): Promise<void> {
    if (this.room === null || this.polling || !this.active) { return; }
    const generation = this.generation;
    this.polling = true;
    try {
      const detail = JSON.parse(await Api.get(`/meetings/${this.room.id}?after=${this.cursor}`)) as Detail;
      if (!this.active || generation !== this.generation) { return; }
      this.room = detail.room;
      this.members = detail.members;
      if (!this.canManage()) {
        this.managingMembers = false;
        this.settings = false;
        this.people = [];
      }
      const known = this.messages.map((message: Message) => message.id);
      this.messages = this.messages.concat(detail.messages.filter((message: Message) => known.indexOf(message.id) < 0));
      this.cursor = detail.cursor;
      if (this.managingMembers) { await this.loadPeople(); }
    } catch (e) {
      if (generation === this.generation) {
        this.error = (e as Error).message;
        if (this.error.includes('请先加入') || this.error.includes('尚未加入')) {
          this.generation++; this.room = null; this.messages = []; this.managingMembers = false;
          await this.loadRooms();
        }
      }
    }
    finally { this.polling = false; }
  }

  private async action(kind: string): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.error = '';
    try {
      if (kind === 'create') {
        const body: CreateRoomRequest = { class_course_id: this.courseId, name: this.title, participant_limit: 20 };
        await Api.post('/meetings', body);
        this.title = '';
        await this.loadRooms();
      } else if (this.room !== null) {
        const id = this.room.id;
        if (kind === 'send') {
          const body: MessageRequest = { content: this.input, immediate: this.immediate };
          await Api.postLong(`/meetings/${id}/messages`, body);
          this.input = '';
        } else if (kind === 'settings') {
          const body: SettingsRequest = { participant_limit: Number(this.capacity), enabled: this.meetingEnabled };
          await Api.put(`/meetings/${id}`, body);
          this.settings = false;
        } else {
          const result = JSON.parse(await Api.postLong(`/meetings/${id}/end`, {} as Record<string, string>)) as Room;
          if (result.status !== 'ended') { this.error = '还有待处理消息，请稍后再次结束会议'; }
        }
        await this.poll();
      }
    } catch (e) { this.error = (e as Error).message; }
    finally { this.busy = false; }
  }

  private canManage(): boolean {
    return this.room !== null && (this.room.creator_id === GlobalState.userId() || GlobalState.canManageCurrentCourse());
  }

  private async loadPeople(): Promise<void> {
    if (this.room === null) { return; }
    const id = this.room.id;
    const generation = this.generation;
    const people = JSON.parse(await Api.get(`/meetings/${id}/members`)) as ManagedMember[];
    if (this.active && generation === this.generation && this.room?.id === id && this.canManage()) { this.people = people; }
  }

  private async exportMinutes(): Promise<void> {
    if (this.busy || this.room === null) { return; }
    this.busy = true;
    try {
      const id = this.room.id;
      const content = await Api.get(`/meetings/${id}/minutes/export`);
      const paths = await new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext)
        .save({ newFileNames: [`meeting-${id}.md`] });
      if (paths.length === 0) { return; }
      const file = await fileIo.open(paths[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { await fileIo.write(file.fd, content); } finally { await fileIo.close(file); }
      this.error = '纪要已导出';
    } catch (e) { this.error = (e as Error).message; }
    finally { this.busy = false; }
  }

  private async memberAction(action: string, userId: number = 0): Promise<void> {
    if (this.busy || this.room === null) { return; }
    const id = this.room.id;
    this.busy = true;
    this.error = '';
    try {
      const body: MemberRequest = { user_id: userId };
      if (action === 'open') { await this.loadPeople(); this.managingMembers = true; }
      else if (action === 'leave') {
        await Api.post(`/meetings/${id}/leave`);
        this.generation++; this.room = null; this.messages = []; this.people = [];
        this.managingMembers = false;
        await this.loadRooms();
      } else {
        if (action === 'remove') { await Api.remove(`/meetings/${id}/members/${userId}`); }
        else { await Api.post(`/meetings/${id}/${action === 'transfer' ? 'owner' : 'members'}`, body); }
        await this.poll();
        if (this.canManage()) { await this.loadPeople(); } else { this.managingMembers = false; }
      }
    } catch (e) { this.error = (e as Error).message; }
    finally { this.busy = false; }
  }

  private confirmMemberAction(action: string, person: ManagedMember): void {
    AlertDialog.show({ title: action === 'transfer' ? '转交主持权' : '移除成员',
      message: action === 'transfer' ? `将主持权转交给 ${person.name}？` : `将 ${person.name} 移出会议？`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '确认', action: () => { this.memberAction(action, person.id); } } });
  }

  build() {
    Row({ space: 16 }) {
      if (!this.compact || this.room === null) {
      Column({ space: 12 }) {
        Text('班级聊天室').fontSize(22).fontWeight(FontWeight.Bold).width('100%')
        if (this.error !== '' && this.room === null) { Text(this.error).fontColor(AppTheme.DANGER).fontSize(13).width('100%') }
        TextInput({ placeholder: '新聊天室名称', text: this.title }).onChange((v: string) => { this.title = v; })
        Button('创建聊天室').fontColor('#FFFFFF').width('100%').backgroundColor(AppTheme.PRIMARY).enabled(!this.busy && this.title.trim() !== '')
          .onClick(() => { this.action('create'); })
        List({ space: 8 }) {
          ForEach(this.rooms, (room: Room) => {
            ListItem() {
              Text(room.name).fontSize(16).width('100%').padding(14)
                .backgroundColor(this.room?.id === room.id ? AppTheme.PRIMARY_LIGHT : '#FFFFFF').borderRadius(8)
            }.onClick(() => { this.selectRoom(room); })
          }, (room: Room) => `${room.id}`)
        }.layoutWeight(1)
      }.width(this.compact ? '100%' : 240).height('100%')
      }
      if (!this.compact || this.room !== null) {
      Column({ space: 12 }) {
        if (this.error !== '') { Text(this.error).fontColor(AppTheme.DANGER).fontSize(13).width('100%') }
        if (this.room === null) {
          Text('暂无选中的聊天室').fontColor(AppTheme.TEXT_TERTIARY)
        } else {
          Row({ space: 8 }) {
            if (this.compact) {
              Button('返回').backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).onClick(() => { this.generation++; this.room = null; this.loadRooms(); })
            }
            Text(this.room.name).fontSize(20).fontWeight(FontWeight.Bold).layoutWeight(1)
          }.width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            Button(this.minutes ? '讨论' : '会议纪要').backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).onClick(() => { this.minutes = !this.minutes; })
            Button('导出纪要').backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4)
              .enabled(!this.busy && this.room.minutes !== '').onClick(() => { this.exportMinutes(); })
            Button('退出会议').backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).enabled(!this.busy).onClick(() => {
              AlertDialog.show({ title: '退出会议', message: '确认退出当前会议？',
                primaryButton: { value: '取消', action: () => {} },
                secondaryButton: { value: '退出', action: () => { this.memberAction('leave'); } } });
            })
            if (this.room.creator_id === GlobalState.userId() || GlobalState.canManageCurrentCourse()) {
              Button('成员管理').backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).enabled(!this.busy).onClick(() => { this.memberAction('open'); })
              Button('设置').backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).onClick(() => { this.settings = !this.settings; })
              Button('结束会议').backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).enabled(!this.busy && this.room.status !== 'ended').onClick(() => { this.action('end'); })
            }
          }.width('100%')
          Text(this.members.map((member: Member) => member.name).join(' · ')).fontSize(12).fontColor(AppTheme.TEXT_TERTIARY).width('100%')
          if (this.settings) {
            Flex({ wrap: FlexWrap.Wrap }) {
              Text('人数上限').fontSize(14)
              TextInput({ text: this.capacity }).width(80).type(InputType.Number).onChange((v: string) => { this.capacity = v; })
              Text('智能体会议').fontSize(14)
              Toggle({ type: ToggleType.Switch, isOn: this.meetingEnabled }).onChange((v: boolean) => { this.meetingEnabled = v; })
              Button('保存').backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).enabled(!this.busy).onClick(() => { this.action('settings'); })
            }
          }
          Scroll() {
            Column({ space: 10 }) {
              if (this.managingMembers) {
                Row() {
                  Text(`会议成员 ${this.members.length} / ${this.room.participant_limit}`).layoutWeight(1)
                  Button('返回讨论').backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).onClick(() => { this.managingMembers = false; })
                }.width('100%')
                ForEach(this.people, (person: ManagedMember) => {
                  Flex({ wrap: FlexWrap.Wrap }) {
                    Text(person.name).fontSize(16).margin(8)
                    Text(person.id === this.room?.creator_id ? '主持人' : person.joined ? '已加入' : person.removed ? '已移除' : '未加入')
                      .fontSize(13).fontColor(AppTheme.TEXT_SECONDARY).margin(8)
                    if (this.room?.status === 'active') {
                      if (!person.joined) {
                        Button('添加').backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).enabled(!this.busy).onClick(() => { this.memberAction('add', person.id); })
                      } else if (person.id !== this.room?.creator_id) {
                        Button('转交主持权').backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).enabled(!this.busy).onClick(() => { this.confirmMemberAction('transfer', person); })
                        if (person.id !== GlobalState.course?.teacher_id && person.id !== GlobalState.userId()) {
                          Button('移除').backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).enabled(!this.busy).fontColor(AppTheme.DANGER).backgroundColor(Color.Transparent)
                            .onClick(() => { this.confirmMemberAction('remove', person); })
                        }
                      }
                    }
                  }.width('100%').padding(8).backgroundColor('#FFFFFF').borderRadius(8)
                }, (person: ManagedMember) => `${person.id}_${person.joined}_${person.removed}_${this.room?.creator_id}`)
              } else if (this.minutes) {
                Text(this.room.minutes || '暂无纪要').width('100%').fontSize(14).copyOption(CopyOptions.InApp)
              } else {
                ForEach(this.messages, (message: Message) => {
                  Column({ space: 6 }) {
                    Text(message.sender_name).fontSize(12).fontColor(AppTheme.PRIMARY_DEEP).width('100%')
                    Text(message.content).fontSize(14).width('100%').copyOption(CopyOptions.InApp)
                  }.width('100%').padding(14).backgroundColor(message.role === 'user' ? '#FFFFFF' : AppTheme.PRIMARY_LIGHT).borderRadius(8)
                }, (message: Message) => `${message.id}`)
              }
            }.width('100%')
          }.layoutWeight(1).width('100%').align(Alignment.Top)
          if (this.room.status === 'active') {
            Row({ space: 8 }) {
              Checkbox({ name: 'immediate' }).select(this.immediate).onChange((v: boolean) => { this.immediate = v; })
              Text('立即邀请智能体').fontSize(13)
            }.width('100%')
            Row({ space: 8 }) {
              TextInput({ placeholder: '消息', text: this.input }).layoutWeight(1).onChange((v: string) => { this.input = v; })
              Button('发送').backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).enabled(!this.busy && this.input.trim() !== '').onClick(() => { this.action('send'); })
            }
          }
        }
      }.layoutWeight(1).height('100%')
      }
    }.padding(24).width('100%').height('100%').backgroundColor(AppTheme.BG_PAGE)
      .onAreaChange((oldArea: Area, newArea: Area) => { this.compact = Number(newArea.width) < 760; })
  }
}
