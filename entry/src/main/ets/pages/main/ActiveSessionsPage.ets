import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import {
  activeSessionError, freshSessionSeconds, inactiveSessionTtlLabel,
  sessionDeviceType, sessionWaitText
} from '../../util/ActiveSessionPresentation';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const CARD_RADIUS: number = 16;
const DANGER: string = '#EF5B5B';
const ONLINE: string = '#34C759';
const WARNING: string = '#F29A2E';
const TTL_DAYS: number[] = [7, 30, 90, 180, 365];
type SessionsLoadState = 'loading' | 'ready' | 'error';

interface SessionRow {
  id: string;
  isCurrent: boolean;
  isPasswordPending: boolean;
  isUnconfirmed: boolean;
  canAcceptSecretChats: boolean;
  canAcceptCalls: boolean;
  type: string;
  apiId: number;
  isOfficialApplication: boolean;
  applicationName: string;
  applicationVersion: string;
  deviceModel: string;
  platform: string;
  systemVersion: string;
  location: string;
  ipAddress: string;
  loginDate: number;
  lastActiveDate: number;
}

function emptySession(): SessionRow {
  return {
    id: '',
    isCurrent: false,
    isPasswordPending: false,
    isUnconfirmed: false,
    canAcceptSecretChats: false,
    canAcceptCalls: false,
    type: '',
    apiId: 0,
    isOfficialApplication: false,
    applicationName: '',
    applicationVersion: '',
    deviceModel: '',
    platform: '',
    systemVersion: '',
    location: '',
    ipAddress: '',
    loginDate: 0,
    lastActiveDate: 0
  };
}

function copySession(row: SessionRow): SessionRow {
  return {
    id: row.id,
    isCurrent: row.isCurrent,
    isPasswordPending: row.isPasswordPending,
    isUnconfirmed: row.isUnconfirmed,
    canAcceptSecretChats: row.canAcceptSecretChats,
    canAcceptCalls: row.canAcceptCalls,
    type: row.type,
    apiId: row.apiId,
    isOfficialApplication: row.isOfficialApplication,
    applicationName: row.applicationName,
    applicationVersion: row.applicationVersion,
    deviceModel: row.deviceModel,
    platform: row.platform,
    systemVersion: row.systemVersion,
    location: row.location,
    ipAddress: row.ipAddress,
    loginDate: row.loginDate,
    lastActiveDate: row.lastActiveDate
  };
}

function sameDay(left: Date, right: Date): boolean {
  return left.getFullYear() === right.getFullYear() &&
    left.getMonth() === right.getMonth() &&
    left.getDate() === right.getDate();
}

function twoDigits(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

function formatClock(seconds: number): string {
  if (seconds <= 0) { return ''; }
  const date = new Date(seconds * 1000);
  const now = new Date();
  const clock = `${twoDigits(date.getHours())}:${twoDigits(date.getMinutes())}`;
  if (sameDay(date, now)) { return `今天 ${clock}`; }
  if (date.getFullYear() === now.getFullYear()) {
    return `${date.getMonth() + 1}月${date.getDate()}日 ${clock}`;
  }
  return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
}

function formatLastActive(seconds: number, isCurrent: boolean): string {
  if (isCurrent) { return '在线'; }
  const now = Math.floor(Date.now() / 1000);
  const diff = Math.max(0, now - seconds);
  if (diff < 60) { return '刚刚在线'; }
  if (diff < 3600) { return `${Math.floor(diff / 60)} 分钟前`; }
  if (diff < 86400) { return `${Math.floor(diff / 3600)} 小时前`; }
  return formatClock(seconds);
}

@Entry
@Component
struct ActiveSessionsPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State current: SessionRow | null = null;
  @State others: SessionRow[] = [];
  @State loadState: SessionsLoadState = 'loading';
  @State loadError: string = '';
  @State syncError: string = '';
  @State refreshing: boolean = false;
  @State linking: boolean = false;
  @State actionKey: string = '';
  @State detailOpen: boolean = false;
  @State selected: SessionRow = emptySession();
  @State inactiveTtlDays: number = 180;
  @State nowSeconds: number = Math.floor(Date.now() / 1000);
  @State serverFreshRestricted: boolean = false;
  private active: boolean = false;
  private loadSequence: number = 0;
  private clockTimer: number = -1;

  @Styles
  pressNormal() {
    .opacity(1).scale({ x: 1, y: 1 })
  }

  @Styles
  pressDown() {
    .opacity(0.7).scale({ x: 0.985, y: 0.985 })
  }

  aboutToAppear(): void {
    this.active = true;
    this.nowSeconds = Math.floor(Date.now() / 1000);
    this.load(true);
    this.clockTimer = setInterval((): void => {
      this.nowSeconds = Math.floor(Date.now() / 1000);
    }, 60000);
  }

  aboutToDisappear(): void {
    this.active = false;
    this.loadSequence += 1;
    if (this.clockTimer !== -1) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
    this.detailOpen = false;
  }

  private parse(session: TdObject): SessionRow {
    return {
      id: `${session['id']}`,
      isCurrent: (session['is_current'] as boolean | undefined) ?? false,
      isPasswordPending: (session['is_password_pending'] as boolean | undefined) ?? false,
      isUnconfirmed: (session['is_unconfirmed'] as boolean | undefined) ?? false,
      canAcceptSecretChats:
        (session['can_accept_secret_chats'] as boolean | undefined) ?? false,
      canAcceptCalls: (session['can_accept_calls'] as boolean | undefined) ?? false,
      type: sessionDeviceType(session),
      apiId: (session['api_id'] as number | undefined) ?? 0,
      isOfficialApplication:
        (session['is_official_application'] as boolean | undefined) ?? false,
      applicationName: (session['application_name'] as string | undefined) ?? '',
      applicationVersion: (session['application_version'] as string | undefined) ?? '',
      deviceModel: (session['device_model'] as string | undefined) ?? '',
      platform: (session['platform'] as string | undefined) ?? '',
      systemVersion: (session['system_version'] as string | undefined) ?? '',
      location: (session['location'] as string | undefined) ?? '',
      ipAddress: (session['ip_address'] as string | undefined) ?? '',
      loginDate: (session['log_in_date'] as number | undefined) ?? 0,
      lastActiveDate: (session['last_active_date'] as number | undefined) ?? 0
    };
  }

  private async load(showLoading: boolean): Promise<void> {
    const sequence = ++this.loadSequence;
    const hasVisibleData = this.current !== null || this.others.length > 0;
    if (showLoading && !hasVisibleData) { this.loadState = 'loading'; }
    else { this.refreshing = true; }
    this.loadError = '';
    try {
      const response = await getTdClient().send(
        { '@type': 'getActiveSessions' } as TdRequest
      );
      const sessions = (response['sessions'] as TdObject[] | undefined) ?? [];
      const rows = sessions.map((session: TdObject): SessionRow => this.parse(session));
      if (!this.active || sequence !== this.loadSequence) { return; }
      const nextCurrent = rows.find((row: SessionRow): boolean => row.isCurrent) ?? null;
      if (nextCurrent === null) {
        throw new Error('CURRENT_SESSION_MISSING');
      }
      this.current = nextCurrent;
      this.others = rows.filter((row: SessionRow): boolean => !row.isCurrent)
        .sort((left: SessionRow, right: SessionRow): number => {
          if (left.isUnconfirmed !== right.isUnconfirmed) {
            return left.isUnconfirmed ? -1 : 1;
          }
          return right.lastActiveDate - left.lastActiveDate;
        });
      this.inactiveTtlDays =
        (response['inactive_session_ttl_days'] as number | undefined) ?? 180;
      this.loadState = 'ready';
      this.syncError = '';
      this.serverFreshRestricted = false;
      if (this.detailOpen && this.selected.id !== '') {
        const updated = rows.find(
          (row: SessionRow): boolean => row.id === this.selected.id
        );
        if (updated === undefined) {
          this.detailOpen = false;
        } else {
          this.selected = copySession(updated);
        }
      }
    } catch (caught) {
      if (!this.active || sequence !== this.loadSequence) { return; }
      const error = caught as Error;
      console.error(`ActiveSessionsPage.getActiveSessions failed: ${error.message}`);
      const presentation = activeSessionError(error.message, '读取登录设备失败，请重试');
      const message = error.message === 'CURRENT_SESSION_MISSING'
        ? '会话信息不完整，请刷新后重试'
        : presentation.text;
      if (hasVisibleData) {
        this.loadState = 'ready';
        this.syncError = message;
      } else {
        this.loadState = 'error';
        this.loadError = message;
      }
    } finally {
      if (this.active && sequence === this.loadSequence) { this.refreshing = false; }
    }
  }

  private titleFor(row: SessionRow): string {
    if (row.deviceModel !== '') { return row.deviceModel; }
    if (row.applicationName !== '') { return row.applicationName; }
    return '未知设备';
  }

  private applicationFor(row: SessionRow): string {
    const app = `${row.applicationName}${row.applicationVersion !== ''
      ? ` ${row.applicationVersion}`
      : ''}`.trim();
    const system = `${row.platform}${row.systemVersion !== ''
      ? ` ${row.systemVersion}`
      : ''}`.trim();
    if (app !== '' && system !== '') { return `${app} · ${system}`; }
    return app !== '' ? app : system;
  }

  private locationFor(row: SessionRow): string {
    if (row.location !== '' && row.ipAddress !== '') {
      return `${row.location} · ${row.ipAddress}`;
    }
    return row.location !== '' ? row.location : row.ipAddress;
  }

  private freshRestrictionSeconds(): number {
    if (this.current === null) { return 0; }
    return freshSessionSeconds((this.current as SessionRow).loginDate, this.nowSeconds);
  }

  private isFreshRestricted(): boolean {
    return this.freshRestrictionSeconds() > 0;
  }

  private freshWaitText(): string {
    return sessionWaitText(this.freshRestrictionSeconds());
  }

  private showFreshRestriction(): void {
    promptAction.showToast({
      message: `Telegram 安全限制：新登录设备需等待 24 小时，预计${this.freshWaitText()}可操作`,
      duration: 3000
    });
  }

  private guardSessionTermination(): boolean {
    if (!this.isFreshRestricted()) { return false; }
    this.showFreshRestriction();
    return true;
  }

  private showMutationError(caught: TdError, fallback: string): void {
    const presentation = activeSessionError(caught.message, fallback);
    if (presentation.kind === 'fresh') { this.serverFreshRestricted = true; }
    promptAction.showToast({ message: presentation.text, duration: 2800 });
    if (presentation.shouldRefresh) { this.load(false); }
  }

  private isMobile(row: SessionRow): boolean {
    const value = `${row.type} ${row.platform} ${row.deviceModel}`.toLowerCase();
    return value.includes('android') || value.includes('iphone') ||
      value.includes('ipad') || value.includes('mobile') ||
      value.includes('harmony') || value.includes('phone');
  }

  private iconColor(row: SessionRow): string {
    const value = `${row.type} ${row.platform}`.toLowerCase();
    if (value.includes('android')) { return '#65C466'; }
    if (value.includes('apple') || value.includes('mac') ||
      value.includes('iphone') || value.includes('ipad')) {
      return '#45BBD6';
    }
    if (value.includes('windows')) { return '#4A90E2'; }
    if (value.includes('harmony')) { return '#ED6C8D'; }
    return '#4CB5E8';
  }

  private unconfirmedSessions(): SessionRow[] {
    return this.others.filter((row: SessionRow): boolean => row.isUnconfirmed);
  }

  private confirmedSessions(): SessionRow[] {
    return this.others.filter((row: SessionRow): boolean => !row.isUnconfirmed);
  }

  private openDetails(row: SessionRow): void {
    this.selected = copySession(row);
    this.detailOpen = true;
  }

  private replaceSession(next: SessionRow): void {
    if (next.isCurrent) {
      this.current = copySession(next);
    } else {
      this.others = this.others.map(
        (row: SessionRow): SessionRow => row.id === next.id ? copySession(next) : row
      );
    }
    if (this.selected.id === next.id) {
      this.selected = copySession(next);
    }
  }

  private async linkDesktopDevice(): Promise<void> {
    if (this.linking || this.actionKey !== '') { return; }
    this.linking = true;
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: true
      };
      const result = await scanBarcode.startScanForResult(
        getContext(this) as common.Context,
        options
      );
      const link = result.originalValue.trim();
      if (link === '') {
        promptAction.showToast({ message: '没有识别到二维码内容', duration: 1800 });
        return;
      }
      const request: TdRequest = { '@type': 'confirmQrCodeAuthentication' };
      request['link'] = link;
      await getTdClient().send(request);
      if (!this.active) { return; }
      promptAction.showToast({ message: '桌面设备已连接', duration: 1800 });
      await this.load(false);
    } catch (caught) {
      const error = caught as BusinessError;
      if (error.code !== 1000500002) {
        console.error(`ActiveSessionsPage.linkDesktopDevice failed: ${error.message}`);
        const presentation = activeSessionError(error.message, '连接设备失败，请重试');
        promptAction.showToast({
          message: presentation.text,
          duration: 2600
        });
      }
    } finally {
      this.linking = false;
    }
  }

  private confirmTerminateAll(): void {
    if (this.others.length === 0 || this.actionKey !== '') { return; }
    if (this.guardSessionTermination()) { return; }
    promptAction.showDialog({
      title: '退出其他所有设备',
      message: '除当前设备外，其他设备都将退出登录。确定继续吗？',
      buttons: [
        { text: '取消', color: COLOR_TEXT_SECONDARY as string },
        { text: '全部退出', color: DANGER }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index === 1) { this.terminateAllOtherSessions(); }
    }).catch((): void => {});
  }

  private async terminateAllOtherSessions(): Promise<void> {
    this.actionKey = 'terminate_all';
    try {
      await getTdClient().send({ '@type': 'terminateAllOtherSessions' } as TdRequest);
      this.others = [];
      this.detailOpen = false;
      promptAction.showToast({ message: '其他设备已全部退出', duration: 1800 });
      await this.load(false);
    } catch (caught) {
      const error = caught as TdError;
      console.error(`ActiveSessionsPage.terminateAll failed: ${error.message}`);
      this.showMutationError(error, '操作失败，请重试');
    } finally {
      this.actionKey = '';
    }
  }

  private confirmTerminate(row: SessionRow): void {
    if (row.isCurrent || this.actionKey !== '') { return; }
    if (this.guardSessionTermination()) { return; }
    promptAction.showDialog({
      title: '终止会话',
      message: `确定让“${this.titleFor(row)}”退出登录吗？`,
      buttons: [
        { text: '取消', color: COLOR_TEXT_SECONDARY as string },
        { text: '终止', color: DANGER }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index === 1) { this.terminateSession(row); }
    }).catch((): void => {});
  }

  private async terminateSession(row: SessionRow): Promise<void> {
    const before = [...this.others];
    this.actionKey = `terminate_${row.id}`;
    try {
      const request: TdRequest = { '@type': 'terminateSession' };
      request['session_id'] = row.id;
      await getTdClient().send(request);
      this.others = this.others.filter(
        (current: SessionRow): boolean => current.id !== row.id
      );
      this.detailOpen = false;
      promptAction.showToast({ message: '该设备已退出', duration: 1800 });
    } catch (caught) {
      const error = caught as TdError;
      console.error(`ActiveSessionsPage.terminateSession failed: ${error.message}`);
      this.others = before;
      this.showMutationError(error, '终止会话失败，请重试');
    } finally {
      this.actionKey = '';
    }
  }

  private async toggleSecretChats(row: SessionRow, enabled: boolean): Promise<void> {
    if (this.actionKey !== '') { return; }
    const before = copySession(row);
    const next = copySession(row);
    next.canAcceptSecretChats = enabled;
    this.replaceSession(next);
    this.actionKey = `secret_${row.id}`;
    try {
      const request: TdRequest = { '@type': 'toggleSessionCanAcceptSecretChats' };
      request['session_id'] = row.id;
      request['can_accept_secret_chats'] = enabled;
      await getTdClient().send(request);
    } catch (caught) {
      const error = caught as TdError;
      console.error(`ActiveSessionsPage.toggleSecretChats failed: ${error.message}`);
      this.replaceSession(before);
      this.showMutationError(error, '设置私密聊天失败');
    } finally {
      this.actionKey = '';
    }
  }

  private async toggleCalls(row: SessionRow, enabled: boolean): Promise<void> {
    if (this.actionKey !== '') { return; }
    const before = copySession(row);
    const next = copySession(row);
    next.canAcceptCalls = enabled;
    this.replaceSession(next);
    this.actionKey = `calls_${row.id}`;
    try {
      const request: TdRequest = { '@type': 'toggleSessionCanAcceptCalls' };
      request['session_id'] = row.id;
      request['can_accept_calls'] = enabled;
      await getTdClient().send(request);
    } catch (caught) {
      const error = caught as TdError;
      console.error(`ActiveSessionsPage.toggleCalls failed: ${error.message}`);
      this.replaceSession(before);
      this.showMutationError(error, '设置接听通话失败');
    } finally {
      this.actionKey = '';
    }
  }

  private async confirmUnconfirmedSession(row: SessionRow): Promise<void> {
    if (!row.isUnconfirmed || this.actionKey !== '') { return; }
    this.actionKey = `confirm_${row.id}`;
    try {
      const request: TdRequest = { '@type': 'confirmSession' };
      request['session_id'] = row.id;
      await getTdClient().send(request);
      const next = copySession(row);
      next.isUnconfirmed = false;
      this.replaceSession(next);
      promptAction.showToast({ message: '登录设备已确认', duration: 1800 });
    } catch (caught) {
      const error = caught as TdError;
      console.error(`ActiveSessionsPage.confirmSession failed: ${error.message}`);
      this.showMutationError(error, '确认设备失败，请重试');
    } finally {
      this.actionKey = '';
    }
  }

  private showTtlMenu(): void {
    if (this.actionKey !== '') { return; }
    promptAction.showActionMenu({
      title: '自动退出不活跃会话',
      buttons: [
        {
          text: this.inactiveTtlDays === 7 ? '✓ 1 周' : '1 周',
          color: COLOR_TEXT_PRIMARY as string
        },
        {
          text: this.inactiveTtlDays === 30 ? '✓ 1 个月' : '1 个月',
          color: COLOR_TEXT_PRIMARY as string
        },
        {
          text: this.inactiveTtlDays === 90 ? '✓ 3 个月' : '3 个月',
          color: COLOR_TEXT_PRIMARY as string
        },
        {
          text: this.inactiveTtlDays === 180 ? '✓ 6 个月' : '6 个月',
          color: COLOR_TEXT_PRIMARY as string
        },
        {
          text: this.inactiveTtlDays >= 365 ? '✓ 1 年' : '1 年',
          color: COLOR_TEXT_PRIMARY as string
        }
      ]
    }).then((result): void => {
      if (result.index >= 0 && result.index < TTL_DAYS.length) {
        this.setInactiveTtl(TTL_DAYS[result.index]);
      }
    }).catch((): void => {});
  }

  private async setInactiveTtl(days: number): Promise<void> {
    if (days === this.inactiveTtlDays) { return; }
    const previous = this.inactiveTtlDays;
    this.inactiveTtlDays = days;
    this.actionKey = 'ttl';
    try {
      const request: TdRequest = { '@type': 'setInactiveSessionTtl' };
      request['inactive_session_ttl_days'] = days;
      await getTdClient().send(request);
      promptAction.showToast({
        message: `已设置为 ${inactiveSessionTtlLabel(days)}`, duration: 1600
      });
    } catch (caught) {
      const error = caught as TdError;
      console.error(`ActiveSessionsPage.setInactiveTtl failed: ${error.message}`);
      this.inactiveTtlDays = previous;
      this.showMutationError(error, '保存自动退出期限失败');
    } finally {
      this.actionKey = '';
    }
  }

  @Builder
  header() {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(26).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(40).height(40).borderRadius(20)
      .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
      .onClick((): void => { router.back(); });
      Text('设备与会话')
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      Stack({ alignContent: Alignment.Center }) {
        if (this.refreshing) {
          LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
        } else {
          SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
            .fontSize(21).fontColor([COLOR_PRIMARY]);
        }
      }
      .width(40).height(40).borderRadius(20)
      .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
      .enabled(!this.refreshing && this.actionKey === '')
      .onClick((): void => { this.load(false); });
    }
    .width('100%').height(52)
    .padding({ left: 8, right: 12 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  sessionIcon(row: SessionRow, size: number) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r(this.isMobile(row)
        ? 'sys.symbol.phone_fill'
        : 'sys.symbol.computer'))
        .fontSize(size * 0.48).fontColor([Color.White]);
    }
    .width(size).height(size).borderRadius(size / 2)
    .backgroundColor(this.iconColor(row));
  }

  @Builder
  linkDeviceCard() {
    Row({ space: 13 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.qrcode'))
          .fontSize(25).fontColor([Color.White]);
      }
      .width(46).height(46).borderRadius(14).backgroundColor(COLOR_PRIMARY);
      Column({ space: 3 }) {
        Text(this.linking ? '正在连接设备…' : '连接桌面设备')
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        Text('扫描 Telegram 桌面端或网页版二维码')
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (this.linking) {
        LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 72 })
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
    .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
    .enabled(!this.linking && this.actionKey === '')
    .onClick((): void => { this.linkDesktopDevice(); });
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .width('100%')
      .fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
      .padding({ left: 16, right: 16, top: 13, bottom: 5 });
  }

  @Builder
  sessionRow(row: SessionRow) {
    Row({ space: 12 }) {
      this.sessionIcon(row, 50);
      Column({ space: 3 }) {
        Row({ space: 8 }) {
          Text(this.titleFor(row))
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          if (row.isCurrent) {
            Text('当前')
              .fontSize(11).fontColor(COLOR_PRIMARY)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor('#164CB5E8').borderRadius(8);
          }
        }
        .width('100%').alignItems(VerticalAlign.Center);
        Text(this.applicationFor(row))
          .fontSize(13).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Row({ space: 5 }) {
          Text(row.location !== '' ? row.location : '未知位置')
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          Text('·').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          Text(row.isUnconfirmed
            ? '等待确认'
            : formatLastActive(row.lastActiveDate, row.isCurrent))
            .fontSize(12)
            .fontColor(row.isCurrent ? ONLINE : (row.isUnconfirmed ? DANGER : COLOR_TEXT_SECONDARY));
        }
        .width('100%').alignItems(VerticalAlign.Center);
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%')
    .padding({ left: 14, right: 13, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
    .onClick((): void => this.openDetails(row));
  }

  @Builder
  currentSessionCard() {
    Column() {
      this.sectionTitle('当前会话');
      if (this.current !== null) {
        this.sessionRow(this.current as SessionRow);
      }
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 76 });
      Row({ space: 13 }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(22).fontColor([DANGER]);
        }.width(34).height(34);
        Column({ space: 2 }) {
          Text('退出其他所有设备')
            .fontSize(16)
            .fontColor(this.others.length > 0 ? DANGER : COLOR_TEXT_SECONDARY);
          if (this.isFreshRestricted()) {
            Text(`安全保护中，${this.freshWaitText()}可用`)
              .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
          }
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1);
        if (this.actionKey === 'terminate_all') {
          LoadingProgress().width(21).height(21).color(DANGER);
        }
      }
      .width('100%')
      .padding({ left: 14, right: 16, top: 11, bottom: 13 })
      .alignItems(VerticalAlign.Center)
      .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
      .enabled(this.others.length > 0 && this.actionKey === '' && !this.isFreshRestricted())
      .onClick((): void => this.confirmTerminateAll());
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(CARD_RADIUS);
  }

  @Builder
  sessionGroupCard(title: string, rows: SessionRow[], warning: boolean) {
    Column() {
      Row({ space: 7 }) {
        if (warning) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
            .fontSize(15).fontColor([WARNING]);
        }
        Text(title)
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(warning ? WARNING : COLOR_PRIMARY);
      }
      .width('100%').padding({ left: 16, right: 16, top: 13, bottom: 5 });
      ForEach(rows, (row: SessionRow, index: number) => {
        if (index > 0) {
          Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 76 });
        }
        this.sessionRow(row);
      }, (row: SessionRow): string => `session_${row.id}`);
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(CARD_RADIUS);
  }

  @Builder
  ttlCard() {
    Column() {
      Row({ space: 13 }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(20).fontColor([Color.White]);
        }
        .width(36).height(36).borderRadius(10)
        .backgroundColor('#8E8E93');
        Column({ space: 2 }) {
          Text('自动退出不活跃会话')
            .fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Text('超过期限未上线的设备将自动退出')
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1);
        if (this.actionKey === 'ttl') {
          LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
        } else {
          Text(inactiveSessionTtlLabel(this.inactiveTtlDays))
            .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14).fontColor([COLOR_TEXT_SECONDARY]);
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)
      .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
      .enabled(this.actionKey === '')
      .onClick((): void => this.showTtlMenu());
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(CARD_RADIUS);
  }

  @Builder
  detailInfoRow(symbol: string, title: string, subtitle: string) {
    Row({ space: 14 }) {
      SymbolGlyph($r(symbol))
        .width(30).fontSize(23).fontColor([COLOR_TEXT_PRIMARY]);
      Column({ space: 3 }) {
        Text(title)
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(subtitle)
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  sessionDetailSheet() {
    Column() {
      Scroll() {
        Column({ space: 3 }) {
          this.sessionIcon(this.selected, 78);
          Text(this.titleFor(this.selected))
            .fontSize(24).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 8 });
          Text(`${this.selected.isCurrent ? '当前设备 · ' : ''}${formatClock(
            this.selected.lastActiveDate
          )}`)
            .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .margin({ bottom: 7 });
          Row({ space: 6 }) {
            if (this.selected.isOfficialApplication) {
              Text('官方应用')
                .fontSize(11).fontColor(COLOR_PRIMARY)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor('#164CB5E8').borderRadius(9);
            } else {
              Text('第三方应用')
                .fontSize(11).fontColor(WARNING)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor('#16F29A2E').borderRadius(9);
            }
            if (this.selected.isUnconfirmed) {
              Text('等待确认')
                .fontSize(11).fontColor(DANGER)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor('#16EF5B5B').borderRadius(9);
            }
            if (this.selected.isPasswordPending) {
              Text('待完成两步验证')
                .fontSize(11).fontColor(WARNING)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor('#16F29A2E').borderRadius(9);
            }
          }
          .margin({ bottom: 12 });

          this.detailInfoRow(
            'sys.symbol.computer',
            this.applicationFor(this.selected) !== ''
              ? this.applicationFor(this.selected)
              : '未知应用',
            '应用与系统'
          );
          Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 62 });
          this.detailInfoRow(
            'sys.symbol.info_circle',
            this.locationFor(this.selected) !== ''
              ? this.locationFor(this.selected)
              : '未知位置',
            '根据 IP 地址估算的位置'
          );
          Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 62 });
          this.detailInfoRow(
            'sys.symbol.clock',
            formatClock(this.selected.loginDate) !== ''
              ? formatClock(this.selected.loginDate)
              : '时间未知',
            '首次登录时间'
          );
          Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 62 });

          Row({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.lock_fill'))
              .width(30).fontSize(23).fontColor([COLOR_TEXT_PRIMARY]);
            Column({ space: 3 }) {
              Text('接受私密聊天').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
              Text('允许在此设备接收新的私密聊天')
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
            }
            .alignItems(HorizontalAlign.Start).layoutWeight(1);
            if (this.actionKey === `secret_${this.selected.id}`) {
              LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
            } else {
              Toggle({
                type: ToggleType.Switch,
                isOn: this.selected.canAcceptSecretChats
              })
                .selectedColor(COLOR_PRIMARY)
                .enabled(this.actionKey === '')
                .onChange((enabled: boolean): void => {
                  this.toggleSecretChats(this.selected, enabled);
                });
            }
          }
          .width('100%')
          .padding({ left: 18, right: 16, top: 11, bottom: 11 })
          .alignItems(VerticalAlign.Center);

          Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 62 });

          Row({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.phone'))
              .width(30).fontSize(23).fontColor([COLOR_TEXT_PRIMARY]);
            Column({ space: 3 }) {
              Text('接听通话').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
              Text('允许在此设备接听 Telegram 通话')
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
            }
            .alignItems(HorizontalAlign.Start).layoutWeight(1);
            if (this.actionKey === `calls_${this.selected.id}`) {
              LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
            } else {
              Toggle({
                type: ToggleType.Switch,
                isOn: this.selected.canAcceptCalls
              })
                .selectedColor(COLOR_PRIMARY)
                .enabled(this.actionKey === '')
                .onChange((enabled: boolean): void => {
                  this.toggleCalls(this.selected, enabled);
                });
            }
          }
          .width('100%')
          .padding({ left: 18, right: 16, top: 11, bottom: 11 })
          .alignItems(VerticalAlign.Center);

          if (this.isFreshRestricted()) {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.info_circle'))
                .fontSize(18).fontColor([COLOR_PRIMARY]);
              Text(`当前会话刚登录，预计${this.freshWaitText()}可终止其他会话；其余设备设置不受影响`)
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                .lineHeight(18).layoutWeight(1);
            }
            .width('calc(100% - 32vp)')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .margin({ left: 16, right: 16, top: 8 })
            .backgroundColor('#124CB5E8')
            .borderRadius(12);
          }

          if (this.selected.isPasswordPending) {
            Text('此设备还需要输入两步验证密码才能完成登录。')
              .width('100%').fontSize(13).fontColor('#FF9500')
              .padding({ left: 18, right: 18, top: 10 });
          }

          if (this.selected.isUnconfirmed) {
            Button(this.actionKey === `confirm_${this.selected.id}`
              ? '正在确认…'
              : '确认此设备登录')
              .width('calc(100% - 32vp)').height(50)
              .fontSize(16).fontColor(Color.White)
              .backgroundColor(COLOR_PRIMARY).borderRadius(25)
              .margin({ left: 16, right: 16, top: 16 })
              .enabled(this.actionKey === '')
              .onClick((): void => {
                this.confirmUnconfirmedSession(this.selected);
              });
          }

          if (!this.selected.isCurrent) {
            Button(this.isFreshRestricted()
              ? `${this.freshWaitText()}可终止`
              : (this.actionKey === `terminate_${this.selected.id}`
                ? '正在终止…'
                : '终止此会话'))
              .width('calc(100% - 32vp)').height(50)
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor(Color.White)
              .backgroundColor(this.isFreshRestricted() ? '#A0A0A5' : DANGER).borderRadius(25)
              .margin({ left: 16, right: 16, top: 16, bottom: 16 })
              .enabled(this.actionKey === '' && !this.isFreshRestricted())
              .onClick((): void => this.confirmTerminate(this.selected));
          } else {
            Text('这是你当前正在使用的设备')
              .width('100%').fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
              .padding({ top: 18, bottom: 18 });
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 16, bottom: this.bottomSafe + 10 });
      }
      .width('100%').layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring);
    }
    .width('100%').height('100%');
  }

  @Builder
  loadingSkeleton() {
    Column({ space: 12 }) {
      Row({ space: 13 }) {
        Row().width(46).height(46).borderRadius(14)
          .backgroundColor($r('app.color.surface_alt'));
        Column({ space: 8 }) {
          Row().width('48%').height(14).borderRadius(7)
            .backgroundColor($r('app.color.surface_alt'));
          Row().width('72%').height(10).borderRadius(5)
            .backgroundColor($r('app.color.surface_alt'));
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      }
      .width('100%').height(72).padding({ left: 14, right: 14 })
      .backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS);
      ForEach([0, 1, 2], (index: number) => {
        Column({ space: 10 }) {
          Row().width(index === 0 ? '32%' : '24%').height(11).borderRadius(6)
            .backgroundColor($r('app.color.surface_alt'));
          Row({ space: 12 }) {
            Circle({ width: 50, height: 50 }).fill($r('app.color.surface_alt'));
            Column({ space: 8 }) {
              Row().width(index === 1 ? '58%' : '46%').height(13).borderRadius(7)
                .backgroundColor($r('app.color.surface_alt'));
              Row().width(index === 1 ? '72%' : '62%').height(10).borderRadius(5)
                .backgroundColor($r('app.color.surface_alt'));
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
          }.width('100%');
        }
        .width('100%').padding(14)
        .backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS);
      }, (index: number): string => `session_skeleton_${index}`);
    }
    .layoutWeight(1).width('100%')
    .padding({ left: 12, right: 12, top: 8 });
  }

  @Builder
  errorState() {
    Column({ space: 11 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
          .fontSize(31).fontColor([WARNING]);
      }
      .width(64).height(64).borderRadius(22).backgroundColor('#16F29A2E');
      Text('设备列表加载失败')
        .fontSize(19).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text(this.loadError !== '' ? this.loadError : '暂时无法读取登录设备，请稍后重试')
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
        .lineHeight(19).textAlign(TextAlign.Center).width('78%');
      Button('重新加载')
        .height(42).padding({ left: 24, right: 24 })
        .fontSize(15).fontColor(Color.White).backgroundColor(COLOR_PRIMARY).borderRadius(21)
        .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
        .onClick((): void => { this.load(true); });
    }
    .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
      curve: Curve.EaseOut
    }));
  }

  @Builder
  syncWarning() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
        .fontSize(17).fontColor([WARNING]);
      Text(this.syncError)
        .fontSize(12).fontColor(COLOR_TEXT_PRIMARY).lineHeight(18).layoutWeight(1);
      Text('重试').fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
        .onClick((): void => { this.load(false); });
    }
    .width('100%').padding({ left: 13, right: 9, top: 9, bottom: 9 })
    .backgroundColor('#14F29A2E').borderRadius(12)
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -4 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 170),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  securityProtectionCard() {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.lock_fill')).fontSize(18).fontColor([COLOR_PRIMARY]);
      }.width(34).height(34).borderRadius(11).backgroundColor('#164CB5E8');
      Column({ space: 3 }) {
        Text('新设备安全保护')
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        Text(this.isFreshRestricted()
          ? `预计${this.freshWaitText()}可终止其他会话；设置与设备确认仍可使用`
          : 'Telegram 暂时拒绝从此设备终止较早的会话，请稍后重试')
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').padding({ left: 13, right: 13, top: 10, bottom: 10 })
    .backgroundColor('#104CB5E8').borderRadius(13);
  }

  @Builder
  noOtherSessionsCard() {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(25).fontColor([ONLINE]);
      }.width(44).height(44).borderRadius(14).backgroundColor('#1634C759');
      Column({ space: 3 }) {
        Text('没有其他活跃会话')
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        Text('目前只有这台设备登录了你的账号')
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS);
  }

  build() {
    Column() {
      this.header();
      if (this.loadState === 'loading') {
        this.loadingSkeleton();
      } else if (this.loadState === 'error') {
        this.errorState();
      } else {
        Scroll() {
          Column({ space: 12 }) {
            if (this.syncError !== '') { this.syncWarning(); }
            this.linkDeviceCard();
            if (this.current !== null) {
              this.currentSessionCard();
              Text('退出其他设备后，它们必须重新登录才能访问你的账号。')
                .width('100%').fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                .padding({ left: 16, right: 16 });
              if (this.isFreshRestricted() || this.serverFreshRestricted) {
                this.securityProtectionCard();
              }
            }
            if (this.unconfirmedSessions().length > 0) {
              this.sessionGroupCard('需要确认', this.unconfirmedSessions(), true);
            }
            if (this.confirmedSessions().length > 0) {
              this.sessionGroupCard('其他活跃会话', this.confirmedSessions(), false);
            }
            if (this.others.length === 0) {
              this.noOtherSessionsCard();
            }
            this.ttlCard();
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: this.bottomSafe + 24 });
        }
        .layoutWeight(1).width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring);
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe })
    .bindSheet($$this.detailOpen, this.sessionDetailSheet(), {
      height: '78%',
      backgroundColor: $r('app.color.surface'),
      dragBar: true
    });
  }
}
