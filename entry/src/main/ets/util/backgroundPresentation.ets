import { TdObject } from '../tdkit/TdTypes';

// Pure mapping from TDLib background objects to what the wallpaper picker can
// render natively (solid / gradient / freeform fills, plus the fill layer
// under patterns). Photo wallpapers surface as kind 'wallpaper' with no
// colors — the picker needs the document file for those.
export interface BackgroundPreview {
  backgroundId: string;
  name: string;
  kind: string; // 'fill' | 'pattern' | 'wallpaper'
  colors: string[];
  angle: number;
  isDark: boolean;
}

export function intToHexColor(value: number): string {
  const clamped = Math.max(0, Math.min(0xFFFFFF, Math.round(value)));
  return `#${clamped.toString(16).toUpperCase().padStart(6, '0')}`;
}

export function fillColorsOf(fill: TdObject | null): string[] {
  if (fill === null) { return []; }
  const typeName = (fill['@type'] as string | undefined) ?? '';
  if (typeName === 'backgroundFillSolid') {
    return [intToHexColor((fill['color'] as number | undefined) ?? 0)];
  }
  if (typeName === 'backgroundFillGradient') {
    return [
      intToHexColor((fill['top_color'] as number | undefined) ?? 0),
      intToHexColor((fill['bottom_color'] as number | undefined) ?? 0)
    ];
  }
  if (typeName === 'backgroundFillFreeformGradient') {
    return ((fill['colors'] as number[] | undefined) ?? [])
      .map((color: number): string => intToHexColor(color));
  }
  return [];
}

function objectOrNull(value: Object | undefined): TdObject | null {
  return value !== undefined && typeof value === 'object' ? value as TdObject : null;
}

// The small preview image TDLib attaches to photo/pattern wallpapers.
export function backgroundThumbnailFile(background: TdObject): TdObject | null {
  const document = objectOrNull(background['document']);
  if (document === null) { return null; }
  const thumbnail = objectOrNull(document['thumbnail']);
  if (thumbnail === null) { return null; }
  return objectOrNull(thumbnail['file']);
}

export function backgroundPreviewOf(background: TdObject): BackgroundPreview | null {
  const type = objectOrNull(background['type']);
  if (type === null) { return null; }
  const typeName = (type['@type'] as string | undefined) ?? '';
  let kind = '';
  let fill: TdObject | null = null;
  if (typeName === 'backgroundTypeFill') {
    kind = 'fill';
    fill = objectOrNull(type['fill']);
  } else if (typeName === 'backgroundTypePattern') {
    kind = 'pattern';
    fill = objectOrNull(type['fill']);
  } else if (typeName === 'backgroundTypeWallpaper') {
    kind = 'wallpaper';
  } else {
    return null;
  }
  return {
    // TDLib serializes int64 ids as strings in JSON — keep them verbatim.
    backgroundId: `${(background['id'] as string | number | undefined) ?? ''}`,
    name: (background['name'] as string | undefined) ?? '',
    kind,
    colors: fillColorsOf(fill),
    angle: fill !== null ? ((fill['rotation_angle'] as number | undefined) ?? 180) : 180,
    isDark: (background['is_dark'] as boolean | undefined) ?? false
  };
}
