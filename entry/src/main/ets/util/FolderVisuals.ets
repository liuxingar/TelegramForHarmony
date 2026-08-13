export interface FolderIconOption {
  name: string;
  label: string;
  emoji: string;
  symbol: Resource;
}

// Telegram folder icons are predefined server-side names; every client renders
// its own local artwork for them. Tintable system symbols keep the look flat
// and consistent with the rest of the UI (color emoji can't be tinted).
export const FOLDER_ICON_OPTIONS: FolderIconOption[] = [
  { name: 'Custom', label: '文件夹', emoji: '📁', symbol: $r('sys.symbol.folder') },
  { name: 'Unread', label: '未读', emoji: '📨', symbol: $r('sys.symbol.envelope') },
  { name: 'Unmuted', label: '提醒', emoji: '🔔', symbol: $r('sys.symbol.bell') },
  { name: 'Private', label: '私聊', emoji: '👤', symbol: $r('sys.symbol.person') },
  { name: 'Groups', label: '群组', emoji: '👥', symbol: $r('sys.symbol.person_2') },
  { name: 'Channels', label: '频道', emoji: '📢', symbol: $r('sys.symbol.speaker_wave_2') },
  { name: 'Bots', label: '机器人', emoji: '🤖', symbol: $r('sys.symbol.robot') },
  { name: 'Favorite', label: '收藏', emoji: '⭐', symbol: $r('sys.symbol.star') },
  { name: 'Work', label: '工作', emoji: '💼', symbol: $r('sys.symbol.briefcase') },
  { name: 'Study', label: '学习', emoji: '📚', symbol: $r('sys.symbol.school') },
  { name: 'Home', label: '家庭', emoji: '🏠', symbol: $r('sys.symbol.house') },
  { name: 'Travel', label: '旅行', emoji: '✈️', symbol: $r('sys.symbol.airplane') },
  { name: 'Game', label: '游戏', emoji: '🎮', symbol: $r('sys.symbol.gamecontroller') },
  { name: 'Sport', label: '运动', emoji: '⚽', symbol: $r('sys.symbol.figure_run') },
  { name: 'Trade', label: '交易', emoji: '📈', symbol: $r('sys.symbol.arrow_up_right') },
  { name: 'Money', label: '财务', emoji: '💰', symbol: $r('sys.symbol.wallet') },
  { name: 'Love', label: '喜欢', emoji: '❤️', symbol: $r('sys.symbol.heart') },
  { name: 'Party', label: '聚会', emoji: '🎉', symbol: $r('sys.symbol.gift') },
  { name: 'Book', label: '阅读', emoji: '📖', symbol: $r('sys.symbol.book') },
  { name: 'Palette', label: '创作', emoji: '🎨', symbol: $r('sys.symbol.paintpalette') },
  // td_api.tl 的 chatFolderIcon 一共定义了 30 个名字。少映射一个，用到它的
  // 文件夹就会掉进兜底的通用文件夹图标 —— 表现是列表里一片一模一样的方框。
  { name: 'All', label: '全部', emoji: '💬', symbol: $r('sys.symbol.message') },
  { name: 'Setup', label: '设置', emoji: '⚙️', symbol: $r('sys.symbol.gearshape') },
  { name: 'Cat', label: '猫', emoji: '🐱', symbol: $r('sys.symbol.pawprint') },
  { name: 'Crown', label: '皇冠', emoji: '👑', symbol: $r('sys.symbol.crown') },
  { name: 'Flower', label: '花', emoji: '🌹', symbol: $r('sys.symbol.flower') },
  { name: 'Mask', label: '面具', emoji: '🎭', symbol: $r('sys.symbol.face') },
  { name: 'Light', label: '灵感', emoji: '💡', symbol: $r('sys.symbol.lightbulb') },
  { name: 'Like', label: '点赞', emoji: '👍', symbol: $r('sys.symbol.hand_thumbsup') },
  { name: 'Note', label: '笔记', emoji: '📝', symbol: $r('sys.symbol.doc_text') },
  { name: 'Airplane', label: '飞机', emoji: '✈️', symbol: $r('sys.symbol.airplane') }
];

export const FOLDER_COLORS: string[] = [
  '#5B8FF9', '#61CDBB', '#F6BD16', '#E8684A', '#9270CA', '#6DC8EC', '#FF7A9A'
];

function optionOf(name: string): FolderIconOption | undefined {
  return FOLDER_ICON_OPTIONS.find((item: FolderIconOption): boolean => item.name === name);
}

export function folderEmoji(name: string): string {
  return optionOf(name)?.emoji ?? '📁';
}

export function folderSymbol(name: string): Resource {
  return optionOf(name)?.symbol ?? $r('sys.symbol.folder');
}

export function folderColor(colorId: number): string {
  return colorId >= 0 && colorId < FOLDER_COLORS.length ? FOLDER_COLORS[colorId] : '#5B8FF9';
}
