import { describe, it, expect, beforeEach } from 'vitest';
import { BackupService } from '../entry/src/main/ets/service/BackupService';
import { pickerState } from './__mocks__/ohos/file/picker';
import { fsState } from './__mocks__/ohos/file/fs';
import { utilState } from './__mocks__/ohos/util';

// importBackup 会触发 DatabaseService.getInstance()（构造期仅建实例，不触库），
// 校验链测试只走文件选择→拷贝→大小→解码→结构校验的前置路径
const fakeCtx = { cacheDir: '/tmp/quiz_cache', filesDir: '/tmp/quiz_files' } as never;

const getImport = () => {
  const svc = BackupService.getInstance();
  return svc.importBackup.bind(svc);
};

const MB = 1024 * 1024;

describe('BackupService.importBackup 校验链', () => {
  beforeEach(() => {
    pickerState.uris = [];
    fsState.statSize = 0;
    fsState.copied = [];
    fsState.deleted = [];
    utilState.decodedText = '';
  });

  it('未选择文件：直接拒绝', async () => {
    const result = await getImport()(fakeCtx);
    expect(result.success).toBe(false);
    expect(result.message).toBe('未选择文件');
    expect(fsState.copied.length).toBe(0);
  });

  it('文件超过 50MB 上限：拒绝且不解码', async () => {
    pickerState.uris = ['file://docs/backup.quizbackup'];
    fsState.statSize = 51 * MB;
    const result = await getImport()(fakeCtx);
    expect(result.success).toBe(false);
    expect(result.message).toContain('备份文件过大');
    expect(utilState.decodedText).toBe('');
  });

  it('version 字段缺失或非法：拒绝', async () => {
    pickerState.uris = ['file://docs/backup.quizbackup'];
    fsState.statSize = 10;
    utilState.decodedText = JSON.stringify({ exportTime: 'x' });
    const result = await getImport()(fakeCtx);
    expect(result.success).toBe(false);
    expect(result.message).toContain('version');
  });

  it('version < 1：拒绝', async () => {
    pickerState.uris = ['file://docs/backup.quizbackup'];
    fsState.statSize = 10;
    utilState.decodedText = JSON.stringify({ version: 0 });
    const result = await getImport()(fakeCtx);
    expect(result.success).toBe(false);
    expect(result.message).toContain('version');
  });

  it('五数组字段缺失：拒绝', async () => {
    pickerState.uris = ['file://docs/backup.quizbackup'];
    fsState.statSize = 10;
    utilState.decodedText = JSON.stringify({
      version: 1, banks: [], questions: [], sessions: [],
      answerRecords: 'not-an-array',   // 数组校验失败点
    });
    const result = await getImport()(fakeCtx);
    expect(result.success).toBe(false);
    expect(result.message).toContain('数据字段');
  });

  it('JSON 损坏：走 catch 分支返回失败', async () => {
    pickerState.uris = ['file://docs/backup.quizbackup'];
    fsState.statSize = 10;
    utilState.decodedText = '{not valid json';
    const result = await getImport()(fakeCtx);
    expect(result.success).toBe(false);
    expect(result.message).toContain('还原失败');
  });
});
