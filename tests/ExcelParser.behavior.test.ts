import { describe, it, expect, beforeEach } from 'vitest';
import { ExcelParser } from '../entry/src/main/ets/service/ExcelParser';
import { QuestionType, Difficulty } from '../entry/src/main/ets/model/Models';
import { fsState } from './__mocks__/ohos/file/fs';
import { utilState } from './__mocks__/ohos/util';

/**
 * ExcelParser 真实解析行为测试（M5）。
 * 经 fs mock 注入 xlsx 内部 XML，走 unzip→sharedStrings→sheet→fieldMap→parseRow 全链路。
 * 关键注入技巧：createTempDir 生成的临时目录名随机，故以"/子路径"后缀键登记内容，
 * 由 fs mock 的 resolveFile 后缀匹配命中。
 */

const TMP = '/data/storage/test/tmp1'; // 沙箱白名单前缀，unzip 校验要求
const ZIP = '/data/storage/test/q.xlsx';

/** 构造 sharedStrings.xml：表头 11 列以共享字符串索引引用（覆盖 t="s" 解析路径） */
const HEADERS = ['题型', '题目', '选项a', '选项b', '选项c', '选项d', '答案', '解析', '分类', '难度', '分值'];
const sharedStringsXml = `<sst>` +
  HEADERS.map(h => `<si><t>${h}</t></si>`).join('') +
  `</sst>`;

/** 构造表头行：11 个单元格全部 t="s" 索引到 sharedStrings */
function headerRow(): string {
  const cols = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K'];
  const cells = HEADERS.map((_, i) =>
    `<c r="${cols[i]}1" t="s"><v>${i}</v></c>`).join('');
  return `<row r="1">${cells}</row>`;
}

/** 构造数据行：inlineStr 类型（覆盖 t="inlineStr" 的 <is><t> 路径） */
function dataRow(r: number, values: (string | null)[]): string {
  const cols = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K'];
  const cells = values.map((v, i) => {
    if (v === null) return '';
    return `<c r="${cols[i]}${r}" t="inlineStr"><is><t>${v}</t></is></c>`;
  }).join('');
  return `<row r="${r}">${cells}</row>`;
}

const sheet1Xml = `<sheetData>` + [
  headerRow(),
  // 行2：单选 + 难度简单 + 分值5
  dataRow(2, ['单选题', '1+1等于多少？', '0', '2', '3', '4', 'B', '正确答案是2', '数学', '简单', '5']),
  // 行3：多选，答案带分隔符需规范化为 ABD
  dataRow(3, ['多选题', '下列哪些是偶数？', '1', '2', '3', '4', 'a, b, d', '2和4', '数学', null, null]),
  // 行4：判断，难度困难
  dataRow(4, ['判断题', '水在100度沸腾', '对', '错', null, null, '对', '常压下成立', '物理', '困难', null]),
  // 行5：脏行——题目为空，应跳过
  dataRow(5, ['单选题', null, null, null, null, null, 'A', null, null, null, null]),
  // 行6：脏行——答案为空，应跳过并记错误
  dataRow(6, ['单选题', '这题没有答案', null, null, null, null, null, null, null, null, null]),
  // 行7：填空，答案保留大小写
  dataRow(7, ['填空题', '输入hello World', null, null, null, null, 'hello World', null, '英语', null, null]),
  // 行8：题型无法识别，应提示并兜底单选
  dataRow(8, ['xxx类型', '未知题型题干', null, null, null, null, 'A', null, null, null, null]),
].join('') + `</sheetData>`;

// Sheet2：题库名在第 2 个单元格
const sheet2Xml = `<sheetData><row r="1"><c r="A1"><v>题库名</v></c><c r="B1"><v>我的题库</v></c></row></sheetData>`;

describe('ExcelParser 解析行为', () => {
  beforeEach(() => {
    fsState.files = {
      '/xl/sharedStrings.xml': sharedStringsXml,
      '/xl/worksheets/sheet1.xml': sheet1Xml,
      '/xl/worksheets/sheet2.xml': sheet2Xml,
    };
    fsState.statSize = 0;
    fsState.accessExists = false;
    fsState.copied = [];
    fsState.deleted = [];
    utilState.decodedText = null; // 走真实 UTF-8 解码
  });

  it('正常解析：题型/难度/分值/答案规范化与题库名', async () => {
    const result = await new ExcelParser().parse(ZIP, TMP);

    // 脏行提示是设计行为（避免静默改写用户数据），此处只断言无解析异常
    expect(result.errors.every(e => !e.includes('解析异常'))).toBe(true);
    expect(result.skipped).toBe(2);
    expect(result.questions.length).toBe(5);
    expect(result.bankName).toBe('我的题库');
  });

  it('单选题：答案大写化，难度与分值正确映射', async () => {
    const [q] = await new ExcelParser().parse(ZIP, TMP).then(r => r.questions);
    expect(q.type).toBe(QuestionType.SINGLE);
    expect(q.question).toBe('1+1等于多少？');
    expect(q.optionA).toBe('0');
    expect(q.optionB).toBe('2');
    expect(q.answer).toBe('B');
    expect(q.explanation).toBe('正确答案是2');
    expect(q.category).toBe('数学');
    expect(q.difficulty).toBe(Difficulty.EASY);
    expect(q.score).toBe(5);
    expect(q.seqNo).toBe(1);
  });

  it('多选题：答案去分隔符并大写（"a, b, d"→"ABD"），难度缺省为中等', async () => {
    const q = (await new ExcelParser().parse(ZIP, TMP)).questions[1];
    expect(q.type).toBe(QuestionType.MULTI);
    expect(q.answer).toBe('ABD');
    expect(q.difficulty).toBe(Difficulty.MEDIUM);
    expect(q.score).toBe(1.0);
  });

  it('判断题：答案规范化为"正确"，难度映射为困难', async () => {
    const q = (await new ExcelParser().parse(ZIP, TMP)).questions[2];
    expect(q.type).toBe(QuestionType.JUDGE);
    expect(q.answer).toBe('正确');
    expect(q.difficulty).toBe(Difficulty.HARD);
  });

  it('填空题：答案保留大小写，不强制大写', async () => {
    const q = (await new ExcelParser().parse(ZIP, TMP)).questions[3];
    expect(q.type).toBe(QuestionType.FILL);
    expect(q.answer).toBe('hello World');
  });

  it('题型无法识别：兜底单选并给出提示，不静默改写', async () => {
    const result = await new ExcelParser().parse(ZIP, TMP);
    const q = result.questions[4];
    expect(q.type).toBe(QuestionType.SINGLE);
    expect(q.question).toBe('未知题型题干');
    expect(result.errors.some(e => e.includes('第 8 行') && e.includes('xxx类型'))).toBe(true);
  });

  it('脏行处理：题目空行与答案空行均跳过，答案空行额外记错误', async () => {
    const result = await new ExcelParser().parse(ZIP, TMP);
    expect(result.skipped).toBe(2);
    expect(result.questions.length).toBe(5);
    expect(result.errors.some(e => e.includes('第 6 行') && e.includes('答案为空'))).toBe(true);
  });

  it('缺少 Sheet1：返回明确错误而非空结果', async () => {
    delete fsState.files['/xl/worksheets/sheet1.xml'];
    const result = await new ExcelParser().parse(ZIP, TMP);
    expect(result.questions).toEqual([]);
    expect(result.errors.some(e => e.includes('无法读取 Sheet1'))).toBe(true);
  });

  it('表头与数据不足：提示格式要求', async () => {
    // 仅一行表头，无数据行
    fsState.files['/xl/worksheets/sheet1.xml'] = `<sheetData>${headerRow()}</sheetData>`;
    const result = await new ExcelParser().parse(ZIP, TMP);
    expect(result.questions).toEqual([]);
    expect(result.errors.some(e => e.includes('数据不足'))).toBe(true);
  });

  it('临时目录被清理（finally 路径）', async () => {
    await new ExcelParser().parse(ZIP, TMP);
    expect(fsState.deleted).toContain(TMP);
  });
});
