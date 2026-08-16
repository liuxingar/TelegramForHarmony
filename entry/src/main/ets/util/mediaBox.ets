// The on-screen size of a message's inline media.
//
// Shared rather than a method on MessageBubble because the prefetcher has to
// arrive at exactly the same numbers: the pixel cache is keyed by path AND
// target size, so a prefetch computed even one pixel differently decodes into a
// second entry that the bubble never asks for — twice the work and no benefit.
//
// It is computable ahead of layout on purpose: every input is the window width
// or a field of the message, never a measured width.

export const MEDIA_MAX_WIDTH: number = 280;
export const MEDIA_MAX_HEIGHT_RATIO: number = 1.2;

export interface MediaBox {
  width: number;
  height: number;
}

export function bubbleMaxWidth(screenW: number): number {
  return screenW * 0.78;
}

export function inlineMaxWidth(screenW: number): number {
  return bubbleMaxWidth(screenW) - 16;
}

export function mediaThumbWidth(screenW: number): number {
  return Math.min(MEDIA_MAX_WIDTH, inlineMaxWidth(screenW));
}

// Extreme source ratios stay visible through Cover cropping without producing
// an unusably narrow/tall bubble. An unknown photo is square; an unknown video
// starts at 16:9 so its placeholder does not jump once the size is known.
export function mediaRatio(photoW: number, photoH: number, isVideo: boolean): number {
  if (photoW > 0 && photoH > 0) {
    return Math.max(0.56, Math.min(2.1, photoW / photoH));
  }
  return isVideo ? 16 / 9 : 1;
}

export function mediaBoxFor(
  screenW: number, photoW: number, photoH: number, isVideo: boolean
): MediaBox {
  const maxW = mediaThumbWidth(screenW);
  const maxH = maxW * MEDIA_MAX_HEIGHT_RATIO;
  const ratio = mediaRatio(photoW, photoH, isVideo);
  let width = maxW;
  let height = width / ratio;
  if (height > maxH) {
    height = maxH;
    width = height * ratio;
  }
  return { width, height };
}
