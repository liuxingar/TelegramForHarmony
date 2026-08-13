import { fileIo as fs, Filter, ListFileOptions } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';

// 扫描 TDLib 落盘目录，列出"本地缓存"条目。
//
// 这件事必须离开 UI 线程：photos 目录在重度使用的账号上轻松到几万个文件
// （实测 29198 个），逐个 statSync 就是几万次 NAPI 往返，同步做会把主线程
// 卡死超过 6 秒，被系统判定 THREAD_BLOCK_6S 直接杀进程。
//
// 两层削减：
//   1. fileSizeOver 过滤下推到原生层 —— 缩略图/头像都小于阈值，在 C++ 侧就
//      被筛掉，不会跨到 JS 侧来。
//   2. 排序和截断也在 worker 里做完，跨线程只回传最终的 maxItems 条。

export interface ScannedFile {
  path: string;
  name: string;
  kind: string; // 'photo' | 'video' | 'file'
  size: number;
  mtimeSec: number;
}

interface ScanDir {
  name: string;
  kind: string;
  // 该目录的体积下限（字节）。0 表示不过滤。
  minBytes: number;
}

@Concurrent
function scanDownloadedFilesTask(
  base: string, minPhotoBytes: number, maxItems: number
): ScannedFile[] {
  const dirs: ScanDir[] = [
    { name: 'videos', kind: 'video', minBytes: 0 },
    { name: 'documents', kind: 'file', minBytes: 0 },
    { name: 'animations', kind: 'video', minBytes: 0 },
    // 自动下载的缩略图全落在 photos 里，占了绝大多数，靠体积把它们挡在原生层。
    { name: 'photos', kind: 'photo', minBytes: minPhotoBytes }
  ];
  const items: ScannedFile[] = [];
  for (const d of dirs) {
    const dir = `${base}/${d.name}`;
    try {
      // minBytes 为 0 时等价于"大于 0 字节"，正好也把空文件挡掉。
      const filter: Filter = { fileSizeOver: d.minBytes };
      const options: ListFileOptions = { filter: filter };
      const names: string[] = fs.listFileSync(dir, options);
      for (const name of names) {
        const path = `${dir}/${name}`;
        try {
          const st = fs.statSync(path);
          if (!st.isFile() || st.size <= 0) {
            continue;
          }
          items.push({ path, name, kind: d.kind, size: st.size, mtimeSec: st.mtime });
        } catch (e) {
          // 单个条目不可读（正在写入 / 已被 TDLib 清理）——跳过，不影响整次扫描。
        }
      }
    } catch (e) {
      // 目录尚未创建 —— 正常情况，跳过。
    }
  }
  items.sort((a: ScannedFile, b: ScannedFile): number => b.mtimeSec - a.mtimeSec);
  return items.slice(0, maxItems);
}

export function scanDownloadedFiles(
  base: string, minPhotoBytes: number, maxItems: number
): Promise<ScannedFile[]> {
  const task: taskpool.Task = new taskpool.Task(
    scanDownloadedFilesTask, base, minPhotoBytes, maxItems);
  return taskpool.execute(task).then((res: Object): ScannedFile[] => res as ScannedFile[]);
}
