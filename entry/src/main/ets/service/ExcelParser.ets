import hilog from '@ohos.hilog';
import { unzip, readTextFile, pathExists, rmdir } from '../utils/ZipUtils';
import { parseXml, findFirst, findAll, findAllDeep } from '../utils/XmlParser';
import { Question, QuestionType, Difficulty } from '../model/Models';

const TAG = 'ExcelParser';
// 防御上限：异常/恶意文件可能携带超大 r 属性（如 r="XFD1048576"），
// 触发巨量空数组预分配导致内存暴涨
const MAX_SHEET_ROWS = 100000;
const MAX_SHEET_COLS = 256;

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

/**
 * 表头是否命中关键词。
 * 'no' 作为子串过于贪婪（'Notes'/'Annotation' 均会命中而误配到 seqNo），
 * 要求其独立成词（前后为词边界，如 'No.'/'Question No' 可命中）。
 */
function matchesKeyword(header: string, kw: string): boolean {
  if (!header.includes(kw)) return false;
  if (kw === 'no') return /\bno\b/.test(header);
  return true;
}

/** 题型文字 → QuestionType；非空但无法识别时返回 null（由调用方提示并兜底） */
function parseType(s: string): QuestionType | null {
  const t = s.toLowerCase().trim();
  if (!t) return QuestionType.SINGLE; // 列缺失/为空按默认单选，不提示
  if (t === 'single' || t.includes('单选')) return QuestionType.SINGLE;
  if (t === 'multi'  || t.includes('多选')) return QuestionType.MULTI;
  if (t === 'judge'  || t.includes('判断')) return QuestionType.JUDGE;
  if (t === 'fill'   || t.includes('填空')) return QuestionType.FILL;
  if (t === 'essay'  || t.includes('简答') || t.includes('论述')) return QuestionType.ESSAY;
  return null;
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

    // OOXML 规范允许省略 r 属性（按出现顺序递增），需维护自增计数器兜底
    let rowCounter = 0;
    for (const row of rows) {
      const rAttr = row.attrs['r'];
      const rowIdx = rAttr ? parseInt(rAttr) - 1 : rowCounter;
      rowCounter = rowIdx + 1;
      if (rowIdx < 0 || rowIdx >= MAX_SHEET_ROWS) {
        // 恶意文件可能写 r="1048576"，按需预分配百万级空行数组
        throw new Error(`表格行号 ${rowIdx + 1} 超出上限（${MAX_SHEET_ROWS} 行），已中止解析`);
      }
      while (result.length <= rowIdx) result.push([]);
      const cells = findAll(row, 'c');
      let colCounter = 0;
      for (const cell of cells) {
        const ref = cell.attrs['r'] ?? '';
        const { col } = ref ? parseCellRef(ref) : { col: colCounter };
        colCounter = col + 1;
        if (col < 0 || col >= MAX_SHEET_COLS) {
          throw new Error(`表格列号 ${col + 1} 超出上限（${MAX_SHEET_COLS} 列），已中止解析`);
        }
        const type = cell.attrs['t'] ?? '';
        let value = '';
        if (type === 'inlineStr') {
          // inlineStr 类型：文本在 <is><t> 子节点内
          const isNode = findFirst(cell, 'is');
          if (isNode) {
            const ts = findAllDeep(isNode, 't');
            value = ts.map(t => t.text).join('');
          }
        } else {
          const vNode = findFirst(cell, 'v');
          value = vNode ? vNode.text : '';
          if (type === 's') {
            // 共享字符串索引
            const idx = parseInt(value);
            value = sharedStrings[idx] ?? '';
          }
        }
        while (result[rowIdx].length <= col) result[rowIdx].push('');
        result[rowIdx][col] = value.trim();
      }
    }
    return result;
  }

  // ── 构建字段映射（列索引 → 字段名） ──
  // 匹配策略（修复短关键词误配，如 'Notes' 命中 'no'、'编号' 抢占复合表头）：
  // 1) 表头与关键词完全一致 → 直接最高优先；
  // 2) 其余在所有命中字段中选“最长关键词”者，同分取声明顺序靠前者；
  // 3) 同一字段仅取首个命中的列（先到先得）。
  private buildFieldMap(headerRow: string[]): Record<string, number> {
    const map: Record<string, number> = {};
    for (let col = 0; col < headerRow.length; col++) {
      const header = headerRow[col].toLowerCase().trim();
      if (!header) continue;
      let bestField = '';
      let bestScore = 0;
      let bestOrder = Number.MAX_SAFE_INTEGER;
      let order = 0;
      for (const [field, keywords] of Object.entries(FIELD_KEYWORDS)) {
        for (const kw of keywords) {
          if (!matchesKeyword(header, kw)) continue;
          const score = kw.length + (header === kw ? 1000 : 0);
          if (score > bestScore || (score === bestScore && order < bestOrder)) {
            bestScore = score;
            bestField = field;
            bestOrder = order;
          }
        }
        order++;
      }
      if (bestField && !(bestField in map)) map[bestField] = col;
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

    // 题型无法识别时提示用户，而非静默按单选处理
    const rawType = get('type');
    let type = parseType(rawType);
    if (type === null) {
      errors.push(`第 ${lineNo} 行：题型“${rawType}”无法识别，已按单选处理`);
      type = QuestionType.SINGLE;
    }
    const difficulty = parseDifficulty(get('difficulty'));
    const scoreStr = get('score');
    const score = scoreStr ? parseFloat(scoreStr) : 1.0;

    const normalizedAnswer = this.normalizeAnswer(answer, type);
    if (type === QuestionType.JUDGE && this.matchJudgeAnswer(answer.trim()) === null) {
      // 判断题答案被兜底为“错误”时明确告知，避免用户数据被静默改写
      errors.push(`第 ${lineNo} 行：判断题答案“${answer.trim()}”无法识别，已按“错误”处理`);
    }

    return {
      type,
      question:    questionText,
      optionA:     get('optionA'),
      optionB:     get('optionB'),
      optionC:     get('optionC'),
      optionD:     get('optionD'),
      optionE:     get('optionE'),
      answer:      normalizedAnswer,
      explanation: get('explanation'),
      category:    get('category'),
      difficulty,
      score:       isNaN(score) ? 1.0 : score,
    };
  }

  // ── 判断题答案匹配：返回 '正确'/'错误'，无法识别返回 null ──
  private matchJudgeAnswer(a: string): '正确' | '错误' | null {
    // 精确匹配，避免 "不对"/"不正确" 被 includes('对') 误判为正确
    const lower = a.toLowerCase();
    const correctSet = ['对', '正确', 't', 'true', '√', '是', 'yes', 'right', 'y', '1'];
    const wrongSet   = ['错', '错误', 'f', 'false', '×', '否', 'no', 'wrong', 'n', '0'];
    if (correctSet.includes(lower) || correctSet.includes(a)) return '正确';
    if (wrongSet.includes(lower) || wrongSet.includes(a)) return '错误';
    // 含"不"前缀的否定（如"不对""不正确"）判错
    if (a.startsWith('不')) return '错误';
    return null;
  }

  // ── 规范化答案格式 ──
  private normalizeAnswer(answer: string, type: QuestionType): string {
    const a = answer.trim();
    if (type === QuestionType.JUDGE) {
      // 无法识别的答案兜底为“错误”，调用方（parseRow）会记录提示
      return this.matchJudgeAnswer(a) ?? '错误';
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
