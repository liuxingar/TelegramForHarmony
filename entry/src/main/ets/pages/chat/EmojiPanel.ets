import {
  KEY_POWER_ACTIVE, KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_MENU,
  KEY_REDUCE_ANIM, powerGroupAnimationDuration
} from '../../store/AppSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { StickerPicker, StickerItem, ClassicPack } from './StickerPicker';
import { GifPicker, GifItem } from './GifPicker';

interface EmojiSection {
  title: string;
  emoji: string[];
}

const SECTIONS: EmojiSection[] = [
  {
    title: '表情与人物',
    emoji: [
      '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃', '😉', '😊',
      '😇', '🥰', '😍', '🤩', '😘', '😗', '☺️', '😚', '😙', '🥲', '😋', '😛',
      '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔', '🤐', '🤨', '😐', '😑',
      '😶', '😏', '😒', '🙄', '😬', '🤥', '😌', '😔', '😪', '🤤', '😴', '😷',
      '🤒', '🤕', '🤢', '🤮', '🤧', '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳',
      '🥸', '😎', '🤓', '🧐', '😕', '😟', '🙁', '☹️', '😮', '😯', '😲', '😳',
      '🥺', '😦', '😧', '😨', '😰', '😥', '😢', '😭', '😱', '😖', '😣', '😞',
      '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '😈', '👿', '💀', '☠️',
      '💩', '🤡', '👹', '👺', '👻', '👽', '👾', '🤖'
    ]
  },
  {
    title: '手势与身体',
    emoji: [
      '👋', '🤚', '🖐️', '✋', '🖖', '👌', '🤌', '🤏', '✌️', '🤞', '🤟', '🤘',
      '🤙', '👈', '👉', '👆', '🖕', '👇', '☝️', '👍', '👎', '✊', '👊', '🤛',
      '🤜', '👏', '🙌', '👐', '🤲', '🤝', '🙏', '✍️', '💅', '🤳', '💪', '🫶',
      '👀', '👁️', '👄', '🧠', '🦾', '🦵'
    ]
  },
  {
    title: '心与符号',
    emoji: [
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❣️', '💕',
      '💞', '💓', '💗', '💖', '💘', '💝', '💟', '💯', '💢', '💥', '💫', '💦',
      '💨', '🕳️', '💣', '💬', '💤', '🔥', '✨', '⭐', '🌟', '⚡', '☄️', '💎'
    ]
  },
  {
    title: '动物与自然',
    emoji: [
      '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮',
      '🐷', '🐸', '🐵', '🙈', '🙉', '🙊', '🐔', '🐧', '🐦', '🐤', '🦆', '🦅',
      '🦉', '🦇', '🐺', '🐗', '🐴', '🦄', '🐝', '🪲', '🦋', '🐢', '🐍', '🐙',
      '🦀', '🐬', '🐳', '🦈', '🌸', '🌹', '🌻', '🌈', '🌙', '☀️'
    ]
  },
  {
    title: '食物与活动',
    emoji: [
      '🍎', '🍊', '🍋', '🍉', '🍇', '🍓', '🍑', '🍍', '🥭', '🥑', '🍅', '🌽',
      '🍔', '🍟', '🍕', '🌭', '🥪', '🌮', '🍜', '🍣', '🍦', '🍰', '🎂', '🍫',
      '☕', '🍺', '🍷', '🥂', '⚽', '🏀', '🏈', '🎾', '🎮', '🎲', '🎯', '🎁',
      '🎉', '🎊', '🎈', '🏆', '🥇', '🚀'
    ]
  }
];

const CLASSIC_PACKS: ClassicPack[] = SECTIONS.map((s: EmojiSection): ClassicPack => ({
  title: s.title,
  icon: s.emoji[0],
  emoji: s.emoji
}));

// Unified emoji/sticker/GIF panel. Tabs stay mounted once visited so switching
// categories doesn't restart requests; the parent link remembers the selected
// category after the panel is closed and reopened.
@Component
export struct EmojiPanel {
  onPick: (emoji: string) => void = (): void => {};
  onPickCustomEmoji: (emoji: string, customEmojiId: string) => void = (): void => {};
  onPickSticker: (s: StickerItem) => void = (): void => {};
  onPickGif: (g: GifItem) => void = (): void => {};
  @Link tab: number;
  @StorageProp(KEY_POWER_ACTIVE) powerSaving: boolean = false;
  @StorageProp(KEY_REDUCE_ANIM) reduceAnimations: boolean = false;
  @State stickerMounted: boolean = false;
  @State gifMounted: boolean = false;

  aboutToAppear(): void {
    this.stickerMounted = this.tab === 1;
    this.gifMounted = this.tab === 2;
  }

  private panelDuration(duration: number): number {
    if (this.reduceAnimations || this.powerSaving) {
      return 0;
    }
    return powerGroupAnimationDuration(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_MENU, duration);
  }

  private switchTab(idx: number): void {
    if (idx === this.tab) {
      return;
    }
    if (idx === 1) {
      this.stickerMounted = true;
    } else if (idx === 2) {
      this.gifMounted = true;
    }
    animateTo({ duration: this.panelDuration(150), curve: Curve.EaseOut }, (): void => {
      this.tab = idx;
    });
  }

  @Builder
  bottomTab(symbol: Resource, label: string, idx: number) {
    Column({ space: 2 }) {
      SymbolGlyph(symbol)
        .fontSize(21)
        .fontColor([this.tab === idx ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY]);
      Text(label)
        .fontSize(11)
        .fontWeight(this.tab === idx ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.tab === idx ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
      Row()
        .width(18).height(2).borderRadius(1)
        .backgroundColor(this.tab === idx ? COLOR_PRIMARY : Color.Transparent);
    }
    .layoutWeight(1).height(48)
    .justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .backgroundColor(this.tab === idx ? $r('app.color.selected_pill') : Color.Transparent)
    .animation({ duration: this.panelDuration(140), curve: Curve.EaseOut })
    .accessibilityText(`${label}${this.tab === idx ? '，已选中' : ''}`)
    .onClick(() => { this.switchTab(idx); });
  }

  build() {
    Column() {
      Stack() {
        Column() {
          StickerPicker({
            stickerType: 'custom_emoji',
            includeTrending: true,
            classicPacks: CLASSIC_PACKS,
            onPick: (s: StickerItem): void => {
              if (s.customEmojiId !== '') {
                this.onPickCustomEmoji(s.emoji, s.customEmojiId);
              } else if (s.emoji !== '') {
                this.onPick(s.emoji);
              }
            }
          });
        }
        .width('100%').height('100%')
        .visibility(this.tab === 0 ? Visibility.Visible : Visibility.Hidden);
        if (this.stickerMounted) {
          Column() {
            StickerPicker({ onPick: (s: StickerItem): void => { this.onPickSticker(s); } });
          }
          .width('100%').height('100%')
          .visibility(this.tab === 1 ? Visibility.Visible : Visibility.Hidden);
        }
        if (this.gifMounted) {
          Column() {
            GifPicker({ onPick: (g: GifItem): void => { this.onPickGif(g); } });
          }
          .width('100%').height('100%')
          .visibility(this.tab === 2 ? Visibility.Visible : Visibility.Hidden);
        }
      }
      // Keep the content viewport explicit. A layoutWeight chain inside the
      // empty-GIF state could otherwise propagate through Stack and make the
      // overlay consume the whole chat page after switching tabs.
      .width('100%').height(241);
      Row({ space: 5 }) {
        this.bottomTab($r('sys.symbol.face_smiling'), '表情', 0);
        this.bottomTab($r('sys.symbol.gift'), '贴纸', 1);
        this.bottomTab($r('sys.symbol.video'), 'GIF', 2);
      }
      .width('100%').height(59)
      .padding({ left: 12, right: 12, top: 5, bottom: 6 })
      .border({ width: { top: 0.7 }, color: $r('app.color.divider') });
    }
    .width('100%').height(300)
    .constraintSize({ minHeight: 300, maxHeight: 300 })
    .backgroundColor($r('app.color.surface'))
    .accessibilityText('表情、贴纸和 GIF 面板');
  }
}
