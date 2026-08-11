import { TdObject } from '../tdkit/TdTypes';
import { intToHexColor } from './backgroundPresentation';

// Accent color ids 0–6 are Telegram's built-in single-color name palette that
// every client hardcodes; ids 7+ arrive with explicit color lists via the
// updateAccentColors push.
const BUILTIN_ACCENTS: string[] = [
  '#E17076', '#FAA774', '#A695E7', '#7BC862', '#6EC9CB', '#65AADD', '#EE7AAE'
];

export interface AccentPreview {
  id: number;
  colors: string[];
}

export function builtinAccentColor(id: number): string {
  return BUILTIN_ACCENTS[((id % BUILTIN_ACCENTS.length) + BUILTIN_ACCENTS.length) %
    BUILTIN_ACCENTS.length];
}

function objectOrNull(value: Object | undefined): TdObject | null {
  return value !== undefined && typeof value === 'object' ? value as TdObject : null;
}

function hexListOf(values: number[] | undefined): string[] {
  return (values ?? []).map((color: number): string => intToHexColor(color));
}

export function accentPreviewOf(accent: TdObject, forDark: boolean): AccentPreview | null {
  const id = (accent['id'] as number | undefined) ?? -1;
  if (id < 0) { return null; }
  const colors = hexListOf(
    accent[forDark ? 'dark_theme_colors' : 'light_theme_colors'] as number[] | undefined
  );
  if (colors.length > 0) {
    return { id, colors };
  }
  const builtin = (accent['built_in_accent_color_id'] as number | undefined) ?? id;
  return { id, colors: [builtinAccentColor(builtin)] };
}

export function profileAccentPreviewOf(
  accent: TdObject, forDark: boolean
): AccentPreview | null {
  const id = (accent['id'] as number | undefined) ?? -1;
  if (id < 0) { return null; }
  const palette = objectOrNull(accent[forDark ? 'dark_theme_colors' : 'light_theme_colors']);
  if (palette === null) { return null; }
  const background = hexListOf(palette['background_colors'] as number[] | undefined);
  const fallback = hexListOf(palette['palette_colors'] as number[] | undefined);
  const colors = background.length > 0 ? background : fallback;
  return colors.length > 0 ? { id, colors } : null;
}
