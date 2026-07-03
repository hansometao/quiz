import hilog from '@ohos.hilog';
import { unzip, readTextFile, pathExists, rmdir } from '../utils/ZipUtils';
import { parseXml, findFirst, findAll, findAllDeep } from '../utils/XmlParser';
import { Question, QuestionType, Difficulty } from '../model/Models';

const TAG = 'ExcelParser';

export interface ParseResult {
  questions: Partial<Question>[];
  skipped: number;
  errors: string[];
  bankName: string;
}

// ─── 列名识别关键词映射 ──────────────────────────────────────

const FIELD_KEYWORDS: Record<string, string[]> = {
  seqNo:       ['序号', 'seq', 'no', '编号'],
  type:        ['题型', 'type', '类型'],
  question:    ['题目', '题干', 'question', '问题', 'stem'],
  optionA:     ['选项a', 'option_a', 'optiona', '选项1', 'a项', 'a选项'],
  optionB:     ['选项b', 'option_b', 'optionb', '选项2', 'b项', 'b选项'],
  optionC:     ['选项c', 'option_c', 'optionc', '选项3', 'c项', 'c选项'],
  optionD:     ['选项d', 'option_d', 'optiond', '选项4', 'd项', 'd选项'],
  optionE:     ['选项e', 'option_e', 'optione', '选项5', 'e项', 'e选项'],
  answer:      ['答案', 'answer', '正确答案', '标准答案'],
  explanation: ['解析', 'explanation', '解题', '分析', '解答', '注解'],
  category:    ['分类', 'category', '章节', '科目', '标签', '类别'],
  difficulty:  ['难度', 'difficulty', '难易'],
  score:       ['分值', 'score', '分数', '配分'],
};

/** 题型文字 → QuestionType */
function parseType(s: string): QuestionType {
  const t = s.toLowerCase().trim();
  if (t === 'single' || t.includes('单选')) return QuestionType.SINGLE;
  if (t === 'multi'  || t.includes('多选')) return QuestionType.MULTI;
  if (t === 'judge'  || t.includes('判断')) return QuestionType.JUDGE;
  if (t === 'fill'   || t.includes('填空')) return QuestionType.FILL;
  if (t === 'essay'  || t.includes('简答') || t.includes('论述')) return QuestionType.ESSAY;
  return QuestionType.SINGLE; // 默认单选
}

/** 难度文字 → Difficulty */
function parseDifficulty(s: string): Difficulty {
  const t = s.toLowerCase().trim();
  if (t === '1' || t.includes('简单') || t.includes('easy'))   return Difficulty.EASY;
  if (t === '3' || t.includes('困难') || t.includes('hard'))   return Difficulty.HARD;
  return Difficulty.MEDIUM;
}

/** 将 Excel 列地址（如 "A"/"AB"）转成列索引（0-based） */
function colLetterToIndex(col: string): number {
  let idx = 0;
  for (const ch of col.toUpperCase()) {
    idx = idx * 26 + (ch.charCodeAt(0) - 64);
  }
  return idx - 1;
}

/** 解析单元格地址，返回 { col: number, row: number }（0-based） */
function parseCellRef(ref: string): { col: number; row: number } {
  const m = ref.match(/^([A-Z]+)(\d+)$/);
  if (!m) return { col: 0, row: 0 };
  return { col: colLetterToIndex(m[1]), row: parseInt(m[2]) - 1 };
}

// ─── 主解析类 ────────────────────────────────────────────────

export class ExcelParser {
  /**
   * 解析 .xlsx 文件
   * @param filePath  设备上的 xlsx 文件绝对路径
   * @param tmpDir    临时解压目录（完成后会被清理）
   */
  async parse(filePath: string, tmpDir: string): Promise<ParseResult> {
    hilog.info(0x0000, TAG, `开始解析: ${filePath}`);
    const result: ParseResult = { questions: [], skipped: 0, errors: [], bankName: '' };

    try {
      // 1. 解压 xlsx
      await unzip(filePath, tmpDir);

      // 2. 读取共享字符串表
      const sharedStrings = this.readSharedStrings(tmpDir);

      // 3. 读取第一个 Sheet XML
      const sheetXml = this.readSheet(tmpDir, 1);
      if (!sheetXml) {
        result.errors.push('无法读取 Sheet1，请确认文件格式正确');
        return result;
      }

      // 4. 解析行列数据
      const rows = this.parseSheetRows(sheetXml, sharedStrings);
      if (rows.length < 2) {
        result.errors.push('Sheet1 数据不足，请确保第一行为表头，后续行为题目数据');
        return result;
      }

      // 5. 识别表头映射
      const headerRow = rows[0];
      const fieldMap = this.buildFieldMap(headerRow);
      hilog.info(0x0000, TAG, `字段映射: ${JSON.stringify(fieldMap)}`);

      // 6. 解析题目行
      for (let i = 1; i < rows.length; i++) {
        const row = rows[i];
        const q = this.parseRow(row, fieldMap, i + 1, result.errors);
        if (q) {
          q.seqNo = i;
          result.questions.push(q);
        } else {
          result.skipped++;
        }
      }

      // 7. 尝试读取题库名（Sheet2 或文件名）
      result.bankName = this.readBankName(tmpDir) || this.extractFileName(filePath);

    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      result.errors.push(`解析异常: ${msg}`);
      hilog.error(0x0000, TAG, `解析失败: ${msg}`);
    } finally {
      // 清理临时目录
      try { rmdir(tmpDir); } catch {}
    }

    hilog.info(0x0000, TAG, `解析完成: ${result.questions.length} 题，跳过 ${result.skipped} 行，错误 ${result.errors.length} 个`);
    return result;
  }

  // ── 读取共享字符串 ──
  private readSharedStrings(tmpDir: string): string[] {
    const path = `${tmpDir}/xl/sharedStrings.xml`;
    if (!pathExists(path)) return [];
    const xml = readTextFile(path);
    const root = parseXml(xml);
    const sis = findAllDeep(root, 'si');
    return sis.map(si => {
      // 收集 <t> 节点文本
      const ts = findAllDeep(si, 't');
      return ts.map(t => t.text).join('');
    });
  }

  // ── 读取指定 Sheet ──
  private readSheet(tmpDir: string, sheetNo: number): string {
    const path = `${tmpDir}/xl/worksheets/sheet${sheetNo}.xml`;
    if (!pathExists(path)) return '';
    return readTextFile(path);
  }

  // ── 解析 Sheet XML → 二维字符串数组 ──
  private parseSheetRows(sheetXml: string, sharedStrings: string[]): string[][] {
    const root = parseXml(sheetXml);
    const sheetData = findFirst(root, 'sheetData');
    if (!sheetData) return [];

    const rows = findAll(sheetData, 'row');
    const result: string[][] = [];

    for (const row of rows) {
      const rowIdx = parseInt(row.attrs['r'] ?? '1') - 1;
      while (result.length <= rowIdx) result.push([]);
      const cells = findAll(row, 'c');
      for (const cell of cells) {
        const ref = cell.attrs['r'] ?? '';
        const { col } = parseCellRef(ref);
        const type = cell.attrs['t'] ?? '';
        const vNode = findFirst(cell, 'v');
        let value = vNode ? vNode.text : '';
        if (type === 's') {
          // 共享字符串索引
          const idx = parseInt(value);
          value = sharedStrings[idx] ?? '';
        }
        while (result[rowIdx].length <= col) result[rowIdx].push('');
        result[rowIdx][col] = value.trim();
      }
    }
    return result;
  }

  // ── 构建字段映射（列索引 → 字段名） ──
  private buildFieldMap(headerRow: string[]): Record<string, number> {
    const map: Record<string, number> = {};
    for (let col = 0; col < headerRow.length; col++) {
      const header = headerRow[col].toLowerCase().trim();
      if (!header) continue;
      for (const [field, keywords] of Object.entries(FIELD_KEYWORDS)) {
        if (keywords.some(kw => header.includes(kw))) {
          if (!(field in map)) map[field] = col;
          break;
        }
      }
    }
    return map;
  }

  // ── 解析单行数据为 Question ──
  private parseRow(row: string[], fieldMap: Record<string, number>, lineNo: number, errors: string[]): Partial<Question> | null {
    const get = (field: string): string => {
      const col = fieldMap[field];
      return col !== undefined ? (row[col] ?? '').trim() : '';
    };

    const questionText = get('question');
    if (!questionText) return null; // 空行直接跳过

    const answer = get('answer');
    if (!answer) {
      errors.push(`第 ${lineNo} 行：答案为空，已跳过`);
      return null;
    }

    const type = parseType(get('type'));
    const difficulty = parseDifficulty(get('difficulty'));
    const scoreStr = get('score');
    const score = scoreStr ? parseFloat(scoreStr) : 1.0;

    return {
      type,
      question:    questionText,
      optionA:     get('optionA'),
      optionB:     get('optionB'),
      optionC:     get('optionC'),
      optionD:     get('optionD'),
      optionE:     get('optionE'),
      answer:      this.normalizeAnswer(answer, type),
      explanation: get('explanation'),
      category:    get('category'),
      difficulty,
      score:       isNaN(score) ? 1.0 : score,
    };
  }

  // ── 规范化答案格式 ──
  private normalizeAnswer(answer: string, type: QuestionType): string {
    const a = answer.trim();
    if (type === QuestionType.JUDGE) {
      // 精确匹配，避免 "不对"/"不正确" 被 includes('对') 误判为正确
      const lower = a.toLowerCase();
      const correctSet = ['对', '正确', 't', 'true', '√', '是', 'yes', 'right', 'y', '1'];
      const wrongSet   = ['错', '错误', 'f', 'false', '×', '否', 'no', 'wrong', 'n', '0'];
      if (correctSet.includes(lower) || correctSet.includes(a)) return '正确';
      if (wrongSet.includes(lower) || wrongSet.includes(a)) return '错误';
      // 含"不"前缀的否定（如"不对""不正确"）判错
      if (a.startsWith('不')) return '错误';
      return '错误';
    }
    if (type === QuestionType.MULTI) {
      // 去除常见分隔符（含中文顿号、分号、斜杠）后大写，如 "A、B,D" → "ABD"
      return a.replace(/[,，;；、\s\/|]/g, '').toUpperCase();
    }
    if (type === QuestionType.FILL) {
      // 填空题保留大小写（答案常为英文单词/代码），不强制大写
      return a;
    }
    return a.toUpperCase();
  }

  // ── 读取 Sheet2 中的题库名 ──
  private readBankName(tmpDir: string): string {
    const sheetXml = this.readSheet(tmpDir, 2);
    if (!sheetXml) return '';
    const root = parseXml(sheetXml);
    const sheetData = findFirst(root, 'sheetData');
    if (!sheetData) return '';
    const rows = findAll(sheetData, 'row');
    if (rows.length === 0) return '';
    const cells = findAll(rows[0], 'c');
    if (cells.length < 2) return '';
    const vNode = findFirst(cells[1], 'v');
    return vNode ? vNode.text.trim() : '';
  }

  private extractFileName(filePath: string): string {
    const parts = filePath.split('/');
    const name = parts[parts.length - 1] ?? '';
    return name.replace(/\.(xlsx|xls)$/i, '');
  }
}
