import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { ComponentContent, UIContext } from '@kit.ArkUI';
import { gradientStops } from './backgroundPresentation';

// Flatten the chat background into one opaque JPEG, once per (background, size).
//
// The live version is a stack: a linear-gradient Column, an Image on top of it
// (for a pattern that Image is a full-screen SVG, which is a lot of paths to
// rasterise), an opacity, an optional blur with an overscan scale, and a
// dimming Column. Every chat that opens builds that stack again, and it stays
// in the compositor underneath a scrolling List for as long as the chat is on
// screen.
//
// None of it is dynamic. Rendering it offscreen once and handing the result to
// a single Image gives the compositor one opaque bitmap instead, which is what
// the layered version was going to be resolved to anyway — just not once per
// frame, per chat.

export interface BackgroundRasterParams {
  colors: string[];
  angle: number;
  path: string;          // '' for a pure gradient
  isPattern: boolean;
  imageOpacity: number;
  dimming: number;
  blurred: boolean;
  width: number;         // vp
  height: number;        // vp
}

// Blur radii. Only a real photo wallpaper (path set, not a pattern) gets
// softened — patterns are line art meant to stay crisp, and a pure gradient
// has no texture to blur. A wallpaper the user (or the sync'd account) marked
// blurred in the official client gets an extra push on top of the baseline.
const NO_BLUR_RADIUS: number = 0;
const WALLPAPER_BLUR_RADIUS: number = 8;
const WALLPAPER_BLURRED_RADIUS: number = 16;

// Pure function: given the shape of the background, decide how much blur (if
// any) the composited image should get. Returns a new value only — no
// mutation of the caller's params.
export function backgroundBlurRadius(path: string, isPattern: boolean, blurred: boolean): number {
  if (path === '' || isPattern) {
    return NO_BLUR_RADIUS;
  }
  return blurred ? WALLPAPER_BLURRED_RADIUS : WALLPAPER_BLUR_RADIUS;
}

// Whether the image needs the overscan that hides the soft edge a blur
// leaves behind. Tied to the same rule as the radius, not to `blurred` alone
// — any nonzero radius (the baseline 8 included) needs it.
function backgroundOverscan(p: BackgroundRasterParams): boolean {
  return backgroundBlurRadius(p.path, p.isPattern, p.blurred) > NO_BLUR_RADIUS;
}

// sig -> file path. The file also survives on disk, but the map is what keeps
// the common case (every chat resolving to the account default) off the disk
// entirely.
const rasterCache: Map<string, string> = new Map();
const inFlight: Set<string> = new Set();
// Offline components are not on the tree, so nothing drives their build/layout
// and resource loading; the capture has to be given time for it. The guide's
// own example uses this order of magnitude.
const SNAPSHOT_DELAY_MS: number = 320;

export function rasterSignature(p: BackgroundRasterParams): string {
  // v3: photo wallpapers now always carry some blur (8, or 16 when the
  // account's own is_blurred flag is set) instead of only the blurred ones.
  // The version token retires every raster cached by the v2 pipeline, which
  // rendered plain wallpapers fully sharp — without bumping it, the map/disk
  // hit would keep serving those sharp files forever.
  const radius: number = backgroundBlurRadius(p.path, p.isPattern, p.blurred);
  return `v3_${p.colors.join('-')}_${p.angle}_${p.path}_${p.isPattern ? 'p' : 'w'}` +
    `_${Math.round(p.imageOpacity * 100)}_${Math.round(p.dimming * 100)}` +
    `_blur${radius}_${Math.round(p.width)}x${Math.round(p.height)}`;
}

export function cachedRaster(sig: string): string {
  return rasterCache.get(sig) ?? '';
}

@Builder
function backgroundLayer(p: BackgroundRasterParams) {
  Stack() {
    if (p.colors.length > 0) {
      Column()
        .width(p.width).height(p.height)
        .linearGradient({ angle: p.angle, colors: gradientStops(p.colors) });
    } else {
      Column().width(p.width).height(p.height).backgroundColor($r('app.color.chat_bg'));
    }
    if (p.path !== '') {
      // Blur softens the edges into the layer underneath, so anything blurred
      // needs the overscan or a faint rim of the gradient/dimming shows through.
      Image(p.path.startsWith('/') ? `file://${p.path}` : p.path).draggable(false)
        .width(p.width).height(p.height)
        .objectFit(p.isPattern ? ImageFit.Contain : ImageFit.Cover)
        .opacity(p.imageOpacity)
        .scale(backgroundOverscan(p) ? { x: 1.08, y: 1.08 } : { x: 1, y: 1 })
        .blur(backgroundBlurRadius(p.path, p.isPattern, p.blurred))
        // 关闭降采样解码：offline 树里 autoResize 会按布局估算把 1157×2560 的
        // 源图解到约一半（实测 652×1443），快照再放大回全屏——用户看到的
        // "背景比实时版糊"就是这个。全分辨率解码 + 高质量插值。
        .autoResize(false)
        .interpolation(ImageInterpolation.High)
        // Offline components decode images on an IO thread by default, so the
        // snapshot would catch the gradient with a hole where the pattern goes.
        .syncLoad(true);
    }
    if (p.dimming > 0) {
      Column().width(p.width).height(p.height)
        .backgroundColor(Color.Black).opacity(p.dimming);
    }
  }
  .width(p.width).height(p.height);
}

// Returns the cached path immediately when there is one, otherwise renders,
// encodes and caches. Returns '' on any failure so the caller keeps the live
// layered rendering — this is an optimisation, never a requirement.
export async function rasterizeBackground(
  ui: UIContext, p: BackgroundRasterParams, cacheDir: string
): Promise<string> {
  const sig = rasterSignature(p);
  const hit = rasterCache.get(sig);
  if (hit !== undefined) {
    return hit;
  }
  if (p.width <= 0 || p.height <= 0 || inFlight.has(sig)) {
    return '';
  }
  inFlight.add(sig);
  let pixelMap: image.PixelMap | undefined = undefined;
  let packer: image.ImagePacker | undefined = undefined;
  try {
    // ComponentContent + wrapBuilder, not a bare arrow calling the @Builder.
    // A global @Builder invoked outside a struct has no component context and
    // throws "Cannot read property observeComponentCreation2 of undefined" —
    // which this function then swallowed, so every chat silently kept the slow
    // layered rendering and the whole optimisation was dead code.
    //
    // The delay gives the offline tree time to build, lay out and load its
    // image; waitUntilRenderFinished makes the capture wait for the draw
    // commands rather than grabbing the previous frame. scale 1 keeps the
    // bitmap at screen size — the guide warns that oversized captures are both
    // wasteful and liable to fail outright.
    const node: ComponentContent<BackgroundRasterParams> =
      new ComponentContent(ui, wrapBuilder(backgroundLayer), p);
    pixelMap = await ui.getComponentSnapshot()
      .createFromComponent(node, SNAPSHOT_DELAY_MS, true,
        { scale: 1, waitUntilRenderFinished: true });
    const dest = `${cacheDir}/chatbg_${sig.replace(/[^A-Za-z0-9_-]/g, '')}.jpg`;
    packer = image.createImagePacker();
    const file = await fileIo.open(dest,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      // Awaited before the PixelMap is released — releasing during an in-flight
      // encode crashes the process.
      await packer.packToFile(pixelMap, file.fd, { format: 'image/jpeg', quality: 96 });
    } finally {
      await fileIo.close(file);
    }
    rasterCache.set(sig, dest);
    return dest;
  } catch (e) {
    console.error(`rasterizeBackground failed: ${e}`);
    return '';
  } finally {
    inFlight.delete(sig);
    if (packer !== undefined) {
      packer.release();
    }
    if (pixelMap !== undefined) {
      pixelMap.release();
    }
  }
}
