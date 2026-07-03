import zlib from '@ohos.zlib';
import fs from '@ohos.file.fs';
import hilog from '@ohos.hilog';

const TAG = 'ZipUtils';

/**
 * 解压 zip/xlsx 文件到指定目录
 * @param zipPath  源文件路径
 * @param destDir  目标目录（解压到此）
 */
export async function unzip(zipPath: string, destDir: string): Promise<void> {
  // 确保目标目录存在
  try {
    fs.mkdirSync(destDir, true);
  } catch {}

  const options: zlib.Options = { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION };
  await zlib.decompressFile(zipPath, destDir, options);
  hilog.info(0x0000, TAG, `解压完成: ${zipPath} → ${destDir}`);
}

/**
 * 读取文件文本内容
 */
export function readTextFile(path: string): string {
  try {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(path);
    const buf = new ArrayBuffer(stat.size);
    fs.readSync(file.fd, buf);
    fs.closeSync(file);
    return bufferToString(buf);
  } catch (e) {
    hilog.warn(0x0000, TAG, `读取文件失败: ${path}`);
    return '';
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
      // 递归删除子项
      const entries = fs.listFileSync(path);
      for (const entry of entries) {
        rmdir(path + '/' + entry);
      }
      fs.rmdirSync(path);
    } else {
      fs.unlinkSync(path);
    }
  } catch (e) {
    hilog.warn(0x0000, TAG, `删除失败: ${path}`);
  }
}

function bufferToString(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  let str = '';
  for (let i = 0; i < bytes.length; i++) {
    str += String.fromCharCode(bytes[i]);
  }
  // 简单 UTF-8 解码（ASCII + 中文）
  try {
    return decodeURIComponent(escape(str));
  } catch {
    return str;
  }
}
