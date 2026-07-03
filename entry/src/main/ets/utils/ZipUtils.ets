import zlib from '@ohos.zlib';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import hilog from '@ohos.hilog';

const TAG = 'ZipUtils';

/**
 * 解压 zip/xlsx 文件到指定目录
 * @param zipPath  源文件路径
 * @param destDir  目标目录（解压到此）
 */
export async function unzip(zipPath: string, destDir: string): Promise<void> {
  try {
    fs.mkdirSync(destDir, true);
  } catch (err) {
    // 目录已存在无需处理，其他错误记录后继续尝试解压
    hilog.debug(0x0000, TAG, `mkdir skipped: ${JSON.stringify(err)}`);
  }

  const options: zlib.Options = { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION };
  await zlib.decompressFile(zipPath, destDir, options);
  hilog.info(0x0000, TAG, `解压完成: ${zipPath} → ${destDir}`);
}

/**
 * 读取文件文本内容（UTF-8 解码，支持多字节字符与 BOM）
 */
export function readTextFile(path: string): string {
  let file;
  try {
    file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(path);
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
 */
export function rmdir(path: string): void {
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
