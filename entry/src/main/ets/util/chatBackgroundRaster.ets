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

// Pattern tile geometry --------------------------------------------------
//
// A pattern document is a small repeatable motif sheet, not a standalone
// photo. The official client tiles it edge-to-edge at a fixed density
// instead of fitting one instance to the screen. Fitting one instance with
// ImageFit.Contain (the old approach) left the screen's off-axis edges bare
// whenever the device was wider (relative to its height) than the pattern's
// own ratio — a tablet, mainly — because Contain picks whichever axis is the
// tighter constraint and leaves the other one short. The gradient's palest
// stop showed through that gap and read as grey padding.
//
// The pattern SVG's native viewBox is 1440x2960 (confirmed by pulling the
// inflated .tgv off a device, see background-diagnosis-report.md) — width:height
// ratio ~0.4865. Every tile keeps that ratio so the motif itself never
// stretches; only the tile COUNT changes with screen size.
const PATTERN_ASPECT: number = 1440 / 2960;
// One tile's height in vp. Chosen to read at roughly the same motif density
// as the official client on a typical phone; screens of any other size just
// get more or fewer tiles, never a stretched or squashed one.
const PATTERN_TILE_HEIGHT_VP: number = 340;

export interface PatternTileGrid {
  cols: number;
  rows: number;
  tileWidth: number;
  tileHeight: number;
}

// Pure function: given a canvas size and a desired tile height, work out how
// many columns/rows of the pattern's own-aspect-ratio tile are needed to
// cover the canvas completely, rounding up so there is never a bare sliver
// on any edge (the grid is then centered and clipped to the canvas, so the
// overrun from rounding is trimmed symmetrically instead of showing as a
// gap on one side).
export function patternTileGrid(
  width: number, height: number, tileHeightVp: number = PATTERN_TILE_HEIGHT_VP
): PatternTileGrid {
  const safeWidth: number = Math.max(width, 1);
  const safeHeight: number = Math.max(height, 1);
  const tileHeight: number = Math.max(tileHeightVp, 1);
  const tileWidth: number = tileHeight * PATTERN_ASPECT;
  const cols: number = Math.max(1, Math.ceil(safeWidth / tileWidth));
  const rows: number = Math.max(1, Math.ceil(safeHeight / tileHeight));
  return { cols, rows, tileWidth, tileHeight };
}

// [0, count) as a fresh array — ForEach needs a concrete array, not a range.
function tileIndices(count: number): number[] {
  const result: number[] = [];
  for (let i = 0; i < count; i++) {
    result.push(i);
  }
  return result;
}

@Builder
export function patternTileGridLayer(path: string, opacity: number, grid: PatternTileGrid) {
  Column() {
    ForEach(tileIndices(grid.rows), (r: number) => {
      Row() {
        ForEach(tileIndices(grid.cols), (c: number) => {
          Image(path.startsWith('/') ? `file://${path}` : path).draggable(false)
            .width(grid.tileWidth).height(grid.tileHeight)
            .objectFit(ImageFit.Cover)
            .autoResize(false)
            .interpolation(ImageInterpolation.High)
            .syncLoad(true);
        }, (c: number): string => `${r}_${c}`);
      }
      .width(grid.cols * grid.tileWidth).height(grid.tileHeight);
    }, (r: number): string => `${r}`);
  }
  .width(grid.cols * grid.tileWidth)
  .height(grid.rows * grid.tileHeight)
  .opacity(opacity);
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
  // v4: patterns are now tiled instead of a single ImageFit.Contain
  // instance (see patternTileGrid()'s comment). The version token retires
  // every raster cached by the v3 pipeline, which baked the Contain
  // letterboxing into the JPEG — without bumping it, the map/disk hit would
  // keep serving those letterboxed files forever.
  //
  // v3: photo wallpapers now always carry some blur (8, or 16 when the
  // account's own is_blurred flag is set) instead of only the blurred ones.
  const radius: number = backgroundBlurRadius(p.path, p.isPattern, p.blurred);
  return `v4_${p.colors.join('-')}_${p.angle}_${p.path}_${p.isPattern ? 'p' : 'w'}` +
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
    if (p.path !== '' && p.isPattern) {
      // Tiled, not a single Contain instance — see the comment above
      // patternTileGrid(). Patterns never carry blur (backgroundBlurRadius
      // is 0 whenever isPattern is true), so there is no overscan/scale to
      // apply here, unlike the wallpaper-photo branch below.
      patternTileGridLayer(p.path, p.imageOpacity, patternTileGrid(p.width, p.height));
    } else if (p.path !== '') {
      // Blur softens the edges into the layer underneath, so anything blurred
      // needs the overscan or a faint rim of the gradient/dimming shows through.
      Image(p.path.startsWith('/') ? `file://${p.path}` : p.path).draggable(false)
        .width(p.width).height(p.height)
        .objectFit(ImageFit.Cover)
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
  .width(p.width).height(p.height)
  // The tile grid's width/height is rounded up to a whole number of tiles
  // and is centered by the Stack's default alignment, so it typically
  // overruns the canvas a little on every edge — clip it back to size
  // instead of letting it push the layer's bounds out.
  .clip(true);
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
