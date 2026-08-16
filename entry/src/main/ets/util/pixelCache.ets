import { image } from '@kit.ImageKit';

// Decode local images ourselves instead of handing a file path to Image.
//
// Why: a PixelMap allocated from shared memory has to be uploaded to a GPU
// texture on the RS main thread every time it is first drawn, and that upload
// is what showed up as stutter while a chat was still loading images. DMA
// memory is zero-copy — the decoder writes into a buffer the GPU reads
// directly — so the upload disappears. The system only picks DMA on its own for
// JPEGs whose source is between 1024 and 8192 px on both axes; chat thumbnails
// sit just under that, so they always landed on the slow path.
//
// Decoding here also lets desiredSize downsample DURING the decode rather than
// scaling a full-size bitmap afterwards, so an album cell no longer decodes a
// whole conversation-sized photo to draw it 90vp wide.
//
// Both wins come from the same call; there is no trade-off to tune.

export interface PixelRequest {
  path: string;      // local file path, no file:// prefix
  width: number;     // target size in PHYSICAL pixels
  height: number;
}

// Handed straight back to the caller, so retaining never has to look the entry
// up again.
//
// The lookup version had a race that showed up as images simply not appearing:
// decode() inserted the entry and then ran eviction, which could drop the entry
// it had just created (nothing referenced it yet) and free its pixels; by the
// time the awaiting component called retain, the key was gone from the map, so
// the reference was never taken and the component was left holding a released
// PixelMap. Passing the entry itself removes the window entirely.
export class PixelHandle {
  readonly pixelMap: image.PixelMap;
  bytes: number = 0;
  // One reference is held by the cache itself while the entry is in the map,
  // plus one per component currently showing it. Pixels are freed when the
  // count reaches zero — so eviction alone never frees something on screen.
  refs: number = 1;
  released: boolean = false;
  // Never evicted. For the chat background: one full-screen bitmap that every
  // chat shares and that costs ~20ms to decode, so letting a long scroll push
  // it out of the LRU would just buy that cost back on the next chat open.
  pinned: boolean = false;

  constructor(pixelMap: image.PixelMap, bytes: number) {
    this.pixelMap = pixelMap;
    this.bytes = bytes;
  }
}

// Decoded pixels are expensive; this is a budget, not an item count. 64MB is
// roughly a screen and a half of full-width chat photos.
const BUDGET_BYTES: number = 64 * 1024 * 1024;

// A decode occupies a worker thread and finishes by handing a bitmap to the
// render pipeline. Letting a fling queue up thirty of them at once means the
// rows that actually stopped on screen wait behind rows the user already went
// past. Three at a time keeps the pipe busy without building that backlog.
const MAX_ACTIVE_DECODES: number = 3;

class PendingDecode {
  req: PixelRequest;
  key: string;
  // How many components are still waiting. A row that scrolls away drops its
  // interest; at zero, a decode that has not started yet is dropped entirely —
  // which is the only point where cancelling actually saves work, since
  // createPixelMap itself cannot be interrupted.
  waiters: number = 1;
  started: boolean = false;
  resolvers: ((handle: PixelHandle | undefined) => void)[] = [];

  constructor(req: PixelRequest, key: string) {
    this.req = req;
    this.key = key;
  }
}

const cache: Map<string, PixelHandle> = new Map();
const pending: Map<string, PendingDecode> = new Map();
const queue: PendingDecode[] = [];
let activeDecodes: number = 0;
let usedBytes: number = 0;

function keyOf(req: PixelRequest): string {
  return `${req.path}@${Math.round(req.width)}x${Math.round(req.height)}`;
}

// Map iterates in insertion order, so the first live entry is the oldest.
// Re-inserting on every hit is what makes that order an LRU.
function touch(key: string, entry: PixelHandle): void {
  cache.delete(key);
  cache.set(key, entry);
}

function decRef(entry: PixelHandle): void {
  entry.refs--;
  if (entry.refs > 0 || entry.released) {
    return;
  }
  entry.released = true;
  try {
    entry.pixelMap.release();
  } catch (e) {
    console.error(`pixelCache release failed: ${e}`);
  }
}

function evictDownTo(limit: number): void {
  for (const key of Array.from(cache.keys())) {
    if (usedBytes <= limit) {
      return;
    }
    const entry = cache.get(key);
    if (entry === undefined || entry.pinned) {
      continue;
    }
    cache.delete(key);
    usedBytes -= entry.bytes;
    // Drops the cache's own reference. Anything still on screen survives on
    // the holders' references and is freed when the last one lets go.
    decRef(entry);
  }
}

// Synchronous hit, for the first build pass of a row that has been shown
// before — going through a Promise there would blank the image for a frame.
export function cachedPixelMap(req: PixelRequest): PixelHandle | undefined {
  const key = keyOf(req);
  const entry = cache.get(key);
  if (entry === undefined) {
    return undefined;
  }
  touch(key, entry);
  return entry;
}

export function loadPixelMap(req: PixelRequest): Promise<PixelHandle | undefined> {
  if (req.path === '' || req.width <= 0 || req.height <= 0) {
    return Promise.resolve(undefined);
  }
  const key = keyOf(req);
  const hit = cache.get(key);
  if (hit !== undefined) {
    touch(key, hit);
    return Promise.resolve(hit);
  }
  // Several rows can ask for the same file in the same frame (an album, or a
  // row rebuilt mid-decode). One decode, shared.
  let task = pending.get(key);
  if (task === undefined) {
    task = new PendingDecode(req, key);
    pending.set(key, task);
    queue.push(task);
    pump();
  } else {
    task.waiters++;
  }
  const waiting = task;
  return new Promise<PixelHandle | undefined>((resolve): void => {
    waiting.resolvers.push(resolve);
  });
}

// Drop this component's interest in a decode. If nobody is left waiting and it
// never started, it leaves the queue and the work is genuinely skipped.
export function cancelPixelMap(req: PixelRequest): void {
  const key = keyOf(req);
  const task = pending.get(key);
  if (task === undefined) {
    return;
  }
  task.waiters--;
  if (task.waiters > 0 || task.started) {
    return;
  }
  const at = queue.indexOf(task);
  if (at >= 0) {
    queue.splice(at, 1);
  }
  pending.delete(key);
  for (const resolve of task.resolvers) {
    resolve(undefined);
  }
}

function settle(task: PendingDecode, handle: PixelHandle | undefined): void {
  pending.delete(task.key);
  for (const resolve of task.resolvers) {
    resolve(handle);
  }
}

function pump(): void {
  while (activeDecodes < MAX_ACTIVE_DECODES && queue.length > 0) {
    // First in, first out. Newest-first looked better during a fling — the
    // latest requests are the rows nearest the viewport — but it can starve an
    // early request indefinitely while new ones keep arriving, and a starved
    // request is a bubble that never draws its photo. Stale work is now
    // removed by cancel() rather than by being outrun, so the queue stays close
    // to the visible set and ordering does not have to compensate.
    const task = queue.shift();
    if (task === undefined) {
      return;
    }
    task.started = true;
    activeDecodes++;
    decode(task.req, task.key).then((handle: PixelHandle | undefined): void => {
      settle(task, handle);
    }).catch((): void => {
      settle(task, undefined);
    }).then((): void => {
      activeDecodes--;
      pump();
    });
  }
}

async function decode(req: PixelRequest, key: string): Promise<PixelHandle | undefined> {
  let source: image.ImageSource | undefined = undefined;
  try {
    source = image.createImageSource(req.path);
    const opts: image.DecodingOptions = {};
    // desiredSize is an exact output size, NOT a bounding box: handing it the
    // display box squeezes the photo into that shape, because the PixelMap
    // itself comes out distorted and ImageFit.Cover has nothing left to crop.
    // Scale the SOURCE dimensions so the result still covers the box at the
    // original aspect ratio, and let Cover do the cropping as before.
    const info = await source.getImageInfo();
    const srcW = info.size.width;
    const srcH = info.size.height;
    if (srcW > 0 && srcH > 0) {
      const scale = Math.min(1, Math.max(req.width / srcW, req.height / srcH));
      opts.desiredSize = {
        width: Math.max(1, Math.round(srcW * scale)),
        height: Math.max(1, Math.round(srcH * scale))
      };
    }
    // AllocatorType.DMA is the point of this whole module. It can legitimately
    // fail — SVG only supports shared memory, and the allocator throws rather
    // than falling back — so a second attempt without the hint keeps those
    // working instead of leaving a blank bubble.
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      pixelMap = await source.createPixelMapUsingAllocator(opts, image.AllocatorType.DMA);
    } catch (dmaError) {
      pixelMap = await source.createPixelMap(opts);
    }
    if (pixelMap === undefined) {
      return undefined;
    }
    const decoded = await pixelMap.getImageInfo();
    // stride, not width: DMA rows are padded to a hardware alignment, and the
    // padding is real memory this budget has to account for.
    const bytes = Math.max(1, decoded.stride) * Math.max(1, decoded.size.height);
    const entry = new PixelHandle(pixelMap, bytes);
    cache.set(key, entry);
    usedBytes += bytes;
    // The extra reference covers the hand-off: eviction below (or any eviction
    // before the caller retains) would otherwise free the entry that this very
    // call is about to return. Dropped once the caller has had its chance.
    entry.refs++;
    evictDownTo(BUDGET_BYTES);
    setTimeout((): void => { decRef(entry); }, 0);
    return entry;
  } catch (e) {
    console.error(`pixelCache decode(${req.path}) failed: ${e}`);
    return undefined;
  } finally {
    if (source !== undefined) {
      try {
        source.release();
      } catch (e) {
        // The PixelMap owns its pixels by now; a failure here is not fatal.
        console.error(`pixelCache source release failed: ${e}`);
      }
    }
  }
}

// A component that has put a PixelMap on screen retains it, and releases when
// it swaps it out or goes away. Taken on the handle rather than a key, so it
// works even for an entry the LRU has already dropped.
export function retainPixelMap(handle: PixelHandle): void {
  handle.refs++;
}

export function releasePixelMap(handle: PixelHandle): void {
  decRef(handle);
}

// Keep this bitmap for the life of the process. Only worth it for something
// both expensive and reused everywhere; anything else should just take the
// normal LRU treatment.
export function pinPixelMap(handle: PixelHandle): void {
  if (!handle.pinned) {
    handle.pinned = true;
    handle.refs++;
  }
}

// Memory pressure (AbilityStage.onMemoryLevel) — drop everything not on screen.
// 内存压力：把没在屏幕上的都交出去。钉住的（背景）不受影响——它是全屏位图，
// 丢了下次开会话又要付 20ms。
export function trimPixelCache(): void {
  evictDownTo(0);
}

export function pixelCacheBytes(): number {
  return usedBytes;
}
