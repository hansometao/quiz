import zlib from '@ohos.zlib';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import hilog from '@ohos.hilog';

const TAG = 'ZipUtils';

/** 单文件文本读取上限（50MB），防止恶意/损坏文件触发 OOM */
const MAX_TEXT_FILE_SIZE = 50 * 1024 * 1024;
/** 解压后总大小上限（200MB），防止 zip bomb */
const MAX_UNCOMPRESSED_SIZE = 200 * 1024 * 1024;
/** 安全删除根目录前缀（沙箱内部路径），禁止删除该前缀之外的路径 */
const SAFE_DELETE_PREFIXES = ['/data/storage/', '/data/app/', '/data/user/'];

/**
 * 解压 zip/xlsx 文件到指定目录
 * @param zipPath  源文件路径
 * @param destDir  目标目录（解压到此）
 */
export async function unzip(zipPath: string, destDir: string): Promise<void> {
  // zip bomb 防护：先校验源文件体积，超大压缩包直接拒绝解压
  try {
    const srcStat = fs.statSync(zipPath);
    if (srcStat.size > MAX_UNCOMPRESSED_SIZE) {
      throw new Error(`源文件过大（${srcStat.size} bytes），可能为 zip bomb，已拒绝解压`);
    }
  } catch (e) {
    hilog.error(0x0000, TAG, `解压前校验失败: ${zipPath}, err: ${JSON.stringify(e)}`);
    throw e;
  }

  try {
    fs.mkdirSync(destDir, true);
  } catch (err) {
    // 目录已存在无需处理，其他错误记录后继续尝试解压
    hilog.debug(0x0000, TAG, `mkdir skipped: ${JSON.stringify(err)}`);
  }

  const options: zlib.Options = { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION };
  await zlib.decompressFile(zipPath, destDir, options);
  // 解压后再次校验：递归累计目录内全部文件总大小，防止压缩比极高的恶意 zip。
  // 注意 fs.statSync(dir).size 返回的是目录元数据大小（通常 4096），并非内部文件总大小，
  // 必须递归遍历 entries 才能得到真实解压体积。
  let totalSize = 0;
  try {
    totalSize = calcDirSize(destDir);
  } catch (e) {
    // 统计失败不阻断流程（可能是权限/符号链接问题），仅记录后跳过校验
    hilog.warn(0x0000, TAG, `解压后体积统计失败: ${JSON.stringify(e)}`);
  }
  if (totalSize > MAX_UNCOMPRESSED_SIZE) {
    // 立即清理已解压内容，避免占用磁盘；抛错让上层感知
    rmdir(destDir);
    throw new Error(`解压后总体积过大（${totalSize} bytes），可能为 zip bomb，已清理`);
  }
  hilog.info(0x0000, TAG, `解压完成: ${zipPath} → ${destDir}（${totalSize} bytes）`);
}

/**
 * 读取文件文本内容（UTF-8 解码，支持多字节字符与 BOM）
 */
export function readTextFile(path: string): string {
  let file;
  try {
    file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(path);
    // 文件大小校验：超过上限直接返回空串，避免分配超大 ArrayBuffer 触发 OOM
    if (stat.size > MAX_TEXT_FILE_SIZE) {
      hilog.warn(0x0000, TAG, `文件过大已拒绝读取: ${path}, size=${stat.size}`);
      return '';
    }
    if (stat.size === 0) return '';
    const buf = new ArrayBuffer(stat.size);
    fs.readSync(file.fd, buf);
    return decodeUtf8(buf);
  } catch (e) {
    hilog.warn(0x0000, TAG, `读取文件失败: ${path}, err: ${JSON.stringify(e)}`);
    return '';
  } finally {
    if (file) {
      try { fs.closeSync(file); } catch {}
    }
  }
}

/**
 * 检查路径是否存在
 */
export function pathExists(path: string): boolean {
  try {
    fs.accessSync(path);
    return true;
  } catch {
    return false;
  }
}

/**
 * 递归删除目录（含文件）
 * 安全限制：仅允许删除沙箱内部路径，拒绝包含路径穿越 .. 的输入，避免误删系统目录
 */
export function rmdir(path: string): void {
  // 路径白名单校验：仅允许沙箱内部路径，禁止 .. 穿越和绝对路径越界
  if (!path || path.includes('..')) {
    hilog.warn(0x0000, TAG, `拒绝删除非法路径: ${path}`);
    return;
  }
  const isSafe = SAFE_DELETE_PREFIXES.some(p => path.startsWith(p));
  if (!isSafe) {
    hilog.warn(0x0000, TAG, `拒绝删除非沙箱路径: ${path}`);
    return;
  }
  try {
    const stat = fs.statSync(path);
    if (stat.isDirectory()) {
      const entries = fs.listFileSync(path);
      for (const entry of entries) {
        rmdir(path + '/' + entry);
      }
      fs.rmdirSync(path);
    } else {
      fs.unlinkSync(path);
    }
  } catch (e) {
    hilog.warn(0x0000, TAG, `删除失败: ${path}, err: ${JSON.stringify(e)}`);
  }
}

/**
 * UTF-8 解码：使用 util.TextDecoder 流式解码，
 * 避免 String.fromCharCode 逐字节拼接的 O(n²) 性能问题，
 * 以及 escape/decodeURIComponent 在多字节边界处的解析失败。
 */
export function decodeUtf8(buf: ArrayBuffer): string {
  const textDecoder = util.TextDecoder.create('utf-8');
  return textDecoder.decodeWithStream(new Uint8Array(buf), { stream: false });
}

/**
 * 递归计算目录内全部文件总大小（字节）。
 * 仅用于解压后体积校验，不导出。遇到目录递归进入，遇到文件累加 stat.size。
 */
function calcDirSize(dirPath: string): number {
  let total = 0;
  const entries = fs.listFileSync(dirPath);
  for (const entry of entries) {
    const full = dirPath + '/' + entry;
    const stat = fs.statSync(full);
    if (stat.isDirectory()) {
      total += calcDirSize(full);
    } else {
      total += stat.size;
    }
  }
  return total;
}
