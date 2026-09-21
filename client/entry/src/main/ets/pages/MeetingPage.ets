import { TouchMotion } from '../common/TouchMotion';
import { MotionPage } from '../common/components/MotionPage';
import { LearningTheme as AppTheme } from '../common/LearningTheme';
import { MobileLayout } from '../common/MobileLayout';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';
import { picker, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

interface Room { id: number; name: string; creator_id: number; status: string; joined: boolean; enabled: boolean; participant_limit: number; minutes: string; room_type: string; agent_mode: string; }
interface Message { id: number; sender_name: string; role: string; content: string; }
interface Member { id: number; name: string; }
interface ManagedMember extends Member { role: string; joined: boolean; removed: boolean; }
interface MemberRequest { user_id: number; }
interface Detail { room: Room; members: Member[]; messages: Message[]; cursor: number; context_limited: boolean; }
interface CreateRoomRequest { class_course_id: number; name: string; participant_limit: number; room_type: string; agent_mode: string; }
interface MessageRequest { content: string; immediate: boolean; }
interface SettingsRequest { participant_limit: number; enabled: boolean; }
interface AgentProfile { id: string; name: string; title: string; personality: string; focus: string; }

@Component
export struct MeetingPage {
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  @Prop roomType: string = 'ai_meeting';
  @State rooms: Room[] = [];
  @State room: Room | null = null;
  @State messages: Message[] = [];
  @State members: Member[] = [];
  @State title: string = '';
  @State input: string = '';
  @State error: string = '';
  @State busy: boolean = false;
  @State minutes: boolean = false;
  @State settings: boolean = false;
  @State capacity: string = '6';
  @State agentMode: string = 'single';
  @State compact: boolean = false;
  @State managingMembers: boolean = false;
  @State people: ManagedMember[] = [];
  @State introWidth: number = 0;
  @State agents: AgentProfile[] = [];
  @State agentError: string = '';
  @State loadingAgents: boolean = false;
  private timer: number = -1;
  private cursor: number = 0;
  private generation: number = 0;
  private polling: boolean = false;
  private active: boolean = true;
  private contextWarningShown: boolean = false;
  private courseId: number = GlobalState.courseId();
  aboutToAppear(): void { this.active = true; this.loadRooms(); if (this.isAiMeeting()) { this.loadAgents(); } this.timer = setInterval(() => { this.poll(); }, 3000); }
  aboutToDisappear(): void { this.active = false; this.generation++; clearInterval(this.timer); }

  private async loadAgents(): Promise<void> {
    if (this.loadingAgents) { return; }
    this.loadingAgents = true;
    this.agentError = '';
    try {
      this.agents = JSON.parse(await Api.get('/chat/agents')) as AgentProfile[];
      if (this.agents.length === 0) { this.agentError = '暂无角色介绍，请重试。'; }
    } catch (e) {
      this.agentError = '角色介绍暂时加载失败，请重试。';
    } finally { this.loadingAgents = false; }
  }

  @Builder
  agentIntroductions() {
    Column({ space: 10 }) {
      Text('四位 AI 学伴').fontSize(17).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK).width('100%')
          if (this.loadingAgents) { Text('正在读取角色介绍…').fontColor(AppTheme.TEXT_SECONDARY) }
          if (this.agentError !== '') {
            Text(this.agentError).fontColor(AppTheme.DANGER)
            Button('重新加载').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).onClick(() => { this.loadAgents(); })
          }
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.agents, (agent: AgentProfile) => {
            Column({ space: 8 }) {
              Text(`${agent.name} · ${agent.title}`).fontSize(14).fontWeight(FontWeight.Bold).fontColor(AppTheme.PRIMARY_DEEP).width('100%')
              Text(agent.personality).fontSize(13).lineHeight(20).fontColor(AppTheme.TEXT_PRIMARY).width('100%')
              Text(`分工：${agent.focus}。`).fontSize(13).lineHeight(20).fontColor(AppTheme.TEXT_SECONDARY).width('100%')
            }.width(this.introWidth >= 900 ? '24%' : this.introWidth >= 520 ? '49%' : '100%')
              .padding(14).margin({ bottom: 10 }).borderRadius(16).backgroundColor(AppTheme.PRIMARY_LIGHT)
          }, (agent: AgentProfile) => agent.id)
        }.width('100%')
        Text('学习记录与总结由独立辅助 LLM 整理；D 负责讨论中的查漏补缺和重点提醒。使用 @组员A 等方式可直接提问。')
          .fontSize(12).lineHeight(19).fontColor(AppTheme.TEXT_SECONDARY).width('100%')
    }.width('100%').padding({ bottom: 12 })
      .onAreaChange((oldArea: Area, area: Area) => { this.introWidth = Number(area.width); })
  }

  private async loadRooms(): Promise<void> {
    try {
      const rooms = JSON.parse(await Api.get(
        `/meetings?class_course_id=${this.courseId}&room_type=${this.roomType}`)) as Room[];
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
      this.contextWarningShown = false;
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
      if (detail.context_limited && !this.contextWarningShown) {
        this.contextWarningShown = true;
        AlertDialog.show({
          title: '本次学习讨论较长',
          message: 'AI 可能无法完整记住较早的讨论。建议导出学习总结，稍作休息后再继续学习。',
          primaryButton: { value: '知道了', action: () => {} }
        });
      }
      if (!this.canManage()) {
        this.managingMembers = false;
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
        const body: CreateRoomRequest = { class_course_id: this.courseId, name: this.title,
          participant_limit: Number(this.capacity), room_type: this.roomType, agent_mode: this.agentMode };
        await Api.post('/meetings', body);
        this.title = '';
        await this.loadRooms();
      } else if (this.room !== null) {
        const id = this.room.id;
        if (kind === 'send') {
          const body: MessageRequest = { content: this.input, immediate: false };
          await Api.postLong(`/meetings/${id}/messages`, body);
          this.input = '';
        } else if (kind === 'settings') {
          const body: SettingsRequest = { participant_limit: Number(this.capacity), enabled: this.isAiMeeting() };
          await Api.put(`/meetings/${id}`, body);
          this.settings = false;
        } else {
          const result = JSON.parse(await Api.postLong(`/meetings/${id}/end`, {} as Record<string, string>)) as Room;
          if (result.status !== 'ended') { this.error = '还有待处理消息，请稍后再次结束讨论'; }
        }
        await this.poll();
      }
    } catch (e) { this.error = (e as Error).message; }
    finally { this.busy = false; }
  }

  private canManage(): boolean {
    return this.room !== null && (this.room.creator_id === GlobalState.userId() || GlobalState.canManageCurrentCourse());
  }

  private isAiMeeting(): boolean {
    return this.roomType === 'ai_meeting';
  }

  private roomLabel(): string {
    return this.isAiMeeting() ? 'AI学习小组' : '聊天群';
  }

  private modeLabel(room: Room): string {
    if (room.room_type === 'group_chat') { return '真人群聊'; }
    return room.agent_mode === 'single' ? '单 AI 伴学' : '多 AI 讨论';
  }

  private validCapacity(): boolean {
    const value: number = Number(this.capacity);
    return value >= 2 && value <= 200 && Math.floor(value) === value;
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
        .save({ newFileNames: [`study-group-${id}.md`] });
      if (paths.length === 0) { return; }
      const file = await fileIo.open(paths[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { await fileIo.write(file.fd, content); } finally { await fileIo.close(file); }
      this.error = '学习总结已导出';
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
    AlertDialog.show({ title: action === 'transfer' ? '转交组长身份' : '移除成员',
      message: action === 'transfer' ? `将组长身份转交给 ${person.name}？` : `将 ${person.name} 移出学习小组？`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '确认', action: () => { this.memberAction(action, person.id); } } });
  }

  build() {
    Row({ space: 16 }) {
      if (!this.compact || this.room === null) {
      Column({ space: 12 }) {
        Text(this.roomLabel()).fontSize(GlobalState.isTeacher() ? 22 : 26).fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.INK).width('100%')
        if (!GlobalState.isTeacher()) {
          Text('和同学交流，让 AI 陪你一起想明白').fontSize(13).fontColor(AppTheme.TEXT_SECONDARY).width('100%')
        }
        if (this.error !== '' && this.room === null) { Text(this.error).fontColor(AppTheme.DANGER).fontSize(13).width('100%') }
        Column({ space: 12 }) {
        if (!GlobalState.isTeacher()) { Text('小组名称').fontSize(13).fontWeight(FontWeight.Medium).fontColor(AppTheme.INK).width('100%') }
        TextInput({ placeholder: `新${this.roomLabel()}名称`, text: this.title })
          .height(44).borderRadius(AppTheme.RADIUS_BTN).backgroundColor(AppTheme.BG_SUNKEN)
          .fontColor(AppTheme.TEXT_PRIMARY).placeholderColor(AppTheme.TEXT_TERTIARY)
          .onChange((v: string) => { this.title = v; })
        Row({ space: 8 }) {
          Text('成员人数上限').fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
          TextInput({ text: this.capacity }).layoutWeight(1).type(InputType.Number)
            .height(44).borderRadius(AppTheme.RADIUS_BTN).backgroundColor(AppTheme.BG_SUNKEN).fontColor(AppTheme.INK)
            .onChange((v: string) => { this.capacity = v; })
        }.width('100%')
        if (this.isAiMeeting()) {
          Row({ space: 8 }) {
            Button('单 AI 伴学').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1)
              .height(44).fontSize(14).borderRadius(AppTheme.RADIUS_BTN)
              .fontColor(this.agentMode === 'single' ? '#FFFFFF' : AppTheme.TEXT_SECONDARY)
              .backgroundColor(this.agentMode === 'single' ? AppTheme.PRIMARY : AppTheme.PRIMARY_LIGHT)
              .onClick(() => { this.agentMode = 'single'; })
            Button('多 AI 讨论').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1)
              .height(44).fontSize(14).borderRadius(AppTheme.RADIUS_BTN)
              .fontColor(this.agentMode === 'multi' ? '#FFFFFF' : AppTheme.TEXT_SECONDARY)
              .backgroundColor(this.agentMode === 'multi' ? AppTheme.PRIMARY : AppTheme.PRIMARY_LIGHT)
              .onClick(() => { this.agentMode = 'multi'; })
          }.width('100%')
          Text(this.agentMode === 'single' ? '普通聊天不会打断，使用 @AI 提问' : '四位 AI 学伴参与讨论，独立辅助 LLM 整理学习记录')
            .fontSize(12).fontColor(AppTheme.TEXT_TERTIARY).width('100%')
          if (this.agentMode === 'multi' && this.compact) {
            Scroll() { this.agentIntroductions() }.height(240).width('100%').align(Alignment.Top)
          }
        }
        Button(`创建${this.roomLabel()}`).stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).fontColor('#FFFFFF').width('100%').backgroundColor(AppTheme.PRIMARY)
          .height(44).fontSize(14).borderRadius(AppTheme.RADIUS_BTN)
          .enabled(!this.busy && this.title.trim() !== '' && this.validCapacity())
          .onClick(() => { this.action('create'); })
        }.width('100%').padding(GlobalState.isTeacher() ? 0 : 16).borderRadius(16)
          .backgroundColor(GlobalState.isTeacher() ? Color.Transparent : AppTheme.BG_CARD)
        if (!GlobalState.isTeacher()) {
          Row() {
            Text('课程小组').fontSize(16).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK).layoutWeight(1)
            Text(`${this.rooms.length} 个`).fontSize(12).fontColor(AppTheme.TEXT_SECONDARY)
          }.width('100%').padding({ top: 8, bottom: 4 })
          if (this.rooms.length === 0 && this.error === '') {
            Text('还没有学习小组，可以创建一个开始讨论。').fontSize(13).lineHeight(21)
              .fontColor(AppTheme.TEXT_SECONDARY).width('100%').padding({ top: 8, bottom: 8 })
          }
        }
        List({ space: 8 }) {
          ForEach(this.rooms, (room: Room) => {
            ListItem() {
              Row() {
                Text(room.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(AppTheme.INK)
                  .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.modeLabel(room)).fontSize(11).fontColor(AppTheme.PRIMARY_DEEP)
              }.width('100%').padding(14)
                .backgroundColor(this.room?.id === room.id ? AppTheme.PRIMARY_LIGHT : '#FFFFFF').borderRadius(AppTheme.RADIUS_BTN)
                .border({ width: 1, color: AppTheme.DIVIDER })
            }.stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'card'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'card')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).onClick(() => { this.selectRoom(room); })
          }, (room: Room) => `${room.id}`)
        }.layoutWeight(1)
      }.width(this.compact ? '100%' : GlobalState.isTeacher() ? 240 : 320).height('100%')
      }
      if (!this.compact || this.room !== null) {
      Column({ space: 12 }) {
        if (this.error !== '') { Text(this.error).fontColor(AppTheme.DANGER).fontSize(13).width('100%') }
        if (this.room === null) {
          if (this.isAiMeeting() && this.agentMode === 'multi') {
            Scroll() { this.agentIntroductions() }.width('100%').layoutWeight(1).align(Alignment.Top)
          } else {
          Column({ space: 24 }) {
            Stack() { SymbolGlyph($r('sys.symbol.person_2')).fontSize(54).fontColor([AppTheme.PRIMARY]) }
              .width(112).height(112).borderRadius(32).backgroundColor(AppTheme.PRIMARY_LIGHT)
              .border({ width: 1, color: '#FFFFFF' }).shadow({ radius: 22, color: '#22436F9D', offsetY: 9 })
            Text('一起把问题想明白').fontSize(28).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
            Text('选择左侧的小组，或创建一次新的学习讨论。').fontSize(15).fontColor(AppTheme.TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
            Column({ space: 16 }) {
              Text('交流观点').fontSize(17).fontWeight(FontWeight.Medium).fontColor(AppTheme.INK).width('100%')
              Text('围绕本课程的问题，与同学分享思路和理解。').fontSize(14).fontColor(AppTheme.TEXT_SECONDARY).width('100%')
              Divider().color(AppTheme.DIVIDER)
              Text('邀请 AI 参与').fontSize(17).fontWeight(FontWeight.Medium).fontColor(AppTheme.INK).width('100%')
              Text('单 AI 模式下使用 @AI 提问；多 AI 模式下由不同角色参与讨论。')
                .fontSize(14).lineHeight(23).fontColor(AppTheme.TEXT_SECONDARY).width('100%')
              Divider().color(AppTheme.DIVIDER)
              Text('带走学习总结').fontSize(17).fontWeight(FontWeight.Medium).fontColor(AppTheme.INK).width('100%')
              Text('讨论后回看总结，保留新的理解与待解决的问题。').fontSize(14).fontColor(AppTheme.TEXT_SECONDARY).width('100%')
            }.width('100%').constraintSize({ maxWidth: 560 }).padding(28).borderRadius(24).backgroundColor('#AFFFFFFF')
          }.width('100%').height('100%').justifyContent(FlexAlign.Center).padding(24)
          }
        } else {
          Row({ space: 8 }) {
            if (this.compact) {
              Button('返回').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).onClick(() => { this.generation++; this.room = null; this.loadRooms(); })
            }
            Text(this.room.name).fontSize(MobileLayout.phone() ? 17 : 20).fontWeight(FontWeight.Bold).layoutWeight(1)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (!MobileLayout.phone()) {
            Text(this.modeLabel(this.room)).fontSize(12).fontColor(AppTheme.PRIMARY_DEEP)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 }).backgroundColor(AppTheme.PRIMARY_LIGHT).borderRadius(6)
            }
            Button('设置').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP)
              .onClick(() => { this.settings = !this.settings; })
          }.width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            if (this.isAiMeeting()) {
              Button(this.minutes ? '讨论' : '学习总结').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).onClick(() => { this.minutes = !this.minutes; })
              Button('导出学习总结').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4)
                .enabled(!this.busy && this.room.minutes !== '').onClick(() => { this.exportMinutes(); })
            }
          }.width('100%')
          Text(`真人成员：${this.members.map((member: Member) => member.name).join(' · ')}`).fontSize(12).fontColor(AppTheme.TEXT_TERTIARY).width('100%')
          if (this.isAiMeeting()) {
            Text(this.room.agent_mode === 'single' ? 'AI 成员：AI助手（被 @AI 时回复）' :
              'AI 学伴：组员A · 组员B · 组员C · 组员D')
              .fontSize(12).fontColor(AppTheme.PRIMARY_DEEP).width('100%')
            Text('学习记录与总结：由独立辅助 LLM 整理').fontSize(12)
              .fontColor(AppTheme.TEXT_SECONDARY).width('100%')
          }
          if (this.settings) {
            Column({ space: 10 }) {
              if (this.canManage()) {
                Row({ space: 8 }) {
                  Text('人数上限').fontSize(14)
                  TextInput({ text: this.capacity }).width(80).type(InputType.Number).onChange((v: string) => { this.capacity = v; })
                  Button('保存').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP)
                    .enabled(!this.busy && this.validCapacity()).onClick(() => { this.action('settings'); })
                }.width('100%')
              }
              Flex({ wrap: FlexWrap.Wrap }) {
                Button(this.isAiMeeting() ? '退出学习小组' : '退出群聊').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY_LIGHT)
                  .fontColor(AppTheme.PRIMARY_DEEP).margin(4).enabled(!this.busy).onClick(() => {
                  AlertDialog.show({ title: this.isAiMeeting() ? '退出学习小组' : '退出群聊', message: `确认退出当前${this.roomLabel()}？`,
                    primaryButton: { value: '取消', action: () => {} },
                    secondaryButton: { value: '退出', action: () => { this.memberAction('leave'); } } });
                })
                if (this.canManage()) {
                  Button('成员管理').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4)
                    .enabled(!this.busy).onClick(() => { this.memberAction('open'); })
                  Button(this.isAiMeeting() ? '结束讨论' : '关闭群聊').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY_LIGHT)
                    .fontColor(AppTheme.DANGER).margin(4).enabled(!this.busy && this.room.status !== 'ended')
                    .onClick(() => { this.action('end'); })
                }
              }.width('100%')
            }.width('100%').padding(12).backgroundColor('#FFFFFF').borderRadius(8)
          }
          Column() {
          MotionPage({ navigationKey: `0|${this.room.id}|${this.minutes}|${this.managingMembers}` }) {
          Scroll() {
            Column({ space: 10 }) {
              if (this.isAiMeeting() && this.room.agent_mode === 'multi' && !this.managingMembers && !this.minutes) {
                this.agentIntroductions()
              }
              if (this.managingMembers) {
                Row() {
                  Text(`真人成员 ${this.members.length} / ${this.room.participant_limit}`).layoutWeight(1)
                  Button('返回讨论').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).onClick(() => { this.managingMembers = false; })
                }.width('100%')
                ForEach(this.people, (person: ManagedMember) => {
                  Flex({ wrap: FlexWrap.Wrap }) {
                    Text(person.name).fontSize(16).margin(8)
                    Text(person.id === this.room?.creator_id ? '组长' : person.joined ? '已加入' : person.removed ? '已移除' : '未加入')
                      .fontSize(13).fontColor(AppTheme.TEXT_SECONDARY).margin(8)
                    if (this.room?.status === 'active') {
                      if (!person.joined) {
                        Button('添加').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).enabled(!this.busy).onClick(() => { this.memberAction('add', person.id); })
                      } else if (person.id !== this.room?.creator_id) {
                        Button('转交组长身份').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).enabled(!this.busy).onClick(() => { this.confirmMemberAction('transfer', person); })
                        if (person.id !== GlobalState.course?.teacher_id && person.id !== GlobalState.userId()) {
                          Button('移除').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).enabled(!this.busy).fontColor(AppTheme.DANGER).backgroundColor(Color.Transparent)
                            .onClick(() => { this.confirmMemberAction('remove', person); })
                        }
                      }
                    }
                  }.width('100%').padding(8).backgroundColor('#FFFFFF').borderRadius(8)
                }, (person: ManagedMember) => `${person.id}_${person.joined}_${person.removed}_${this.room?.creator_id}`)
              } else if (this.minutes && this.isAiMeeting()) {
                Text(this.room.minutes || '暂无学习总结').width('100%').fontSize(14).copyOption(CopyOptions.InApp)
              } else {
                ForEach(this.messages, (message: Message) => {
                  Column({ space: 6 }) {
                    Text(message.sender_name).fontSize(12).fontColor(AppTheme.PRIMARY_DEEP).width('100%')
                    Text(message.content).fontSize(15).lineHeight(24).fontColor(AppTheme.TEXT_PRIMARY)
                      .width('100%').copyOption(CopyOptions.InApp)
                  }.width('100%').padding(14).backgroundColor(message.role === 'user' ? '#FFFFFF' : AppTheme.PRIMARY_LIGHT).borderRadius(8)
                }, (message: Message) => `${message.id}`)
              }
            }.width('100%')
          }.width('100%').height('100%').align(Alignment.Top)
          }
          }.layoutWeight(1).width('100%')
          if (this.room.status === 'active') {
            Row({ space: 8 }) {
              TextInput({ placeholder: this.isAiMeeting() ?
                (this.room.agent_mode === 'single' ? '消息；使用 @AI 提问' : '消息；@组员A 可直接提问') : '消息', text: this.input })
                .layoutWeight(1).onChange((v: string) => { this.input = v; })
              Button('发送').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP).margin(4).enabled(!this.busy && this.input.trim() !== '').onClick(() => { this.action('send'); })
            }
          }
        }
      }.layoutWeight(1).height('100%').padding(this.compact ? 12 : 24).borderRadius(28)
        .backgroundColor(GlobalState.isTeacher() ? Color.Transparent : '#BFFFFFFF')
        .border({ width: GlobalState.isTeacher() ? 0 : 1, color: '#F0FFFFFF' })
      }
    }.padding(MobileLayout.phone() ? 16 : 24).width('100%').height('100%').backgroundColor(AppTheme.BG_PAGE)
      .onAreaChange((oldArea: Area, newArea: Area) => { this.compact = Number(newArea.width) < 760; })
  }
}
