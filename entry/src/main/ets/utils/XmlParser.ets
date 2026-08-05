/**
 * 极简 XML 解析器（专为解析 .xlsx 内部 XML 使用）
 * 不依赖任何第三方库，纯字符串解析
 */

export interface XmlNode {
  tag: string;
  attrs: Record<string, string>;
  text: string;
  children: XmlNode[];
}

/** XML 节点数量上限，防止恶意/损坏 XML 耗尽内存 */
const MAX_XML_NODES = 500000;

/**
 * 解析 XML 字符串为节点树
 */
export function parseXml(xml: string): XmlNode {
  // 去掉 XML 声明和命名空间前缀（同时匹配单双引号的 xmlns 声明）
  let src = xml
    .replace(/<\?xml[^>]*\?>/g, '')
    .replace(/\s+xmlns[^=]*=(?:"[^"]*"|'[^']*')/g, '')
    .replace(/<(\/?)\w+:/g, '<$1');   // 去掉命名空间前缀如 <x:workbook>

  const root: XmlNode = { tag: 'root', attrs: {}, text: '', children: [] };
  const stack: XmlNode[] = [root];
  let nodeCount = 0;

  // 简单状态机：逐字符扫描标签
  let i = 0;
  while (i < src.length) {
    if (src[i] === '<') {
      // CDATA 段：必须用 ]]> 定位结束，避免内部 > 截断
      if (src.startsWith('<![CDATA[', i)) {
        const end = src.indexOf(']]>', i + 9);
        if (end === -1) break;
        const content = src.slice(i + 9, end);
        const current = stack[stack.length - 1];
        if (current) current.text += content;
        i = end + 3;
        continue;
      }
      // 注释：用 --> 定位结束，避免内部 > 截断
      if (src.startsWith('<!--', i)) {
        const end = src.indexOf('-->', i + 4);
        i = end === -1 ? src.length : end + 3;
        continue;
      }
      // DOCTYPE 声明：可能包含内部子集 [ ... ]，需匹配对应 > 结束，
      // 简单处理：扫描时同样跳过引号内的 >，避免被内部子集截断
      if (src.startsWith('<!DOCTYPE', i) || src.startsWith('<!doctype', i)) {
        let end = -1;
        let inQuote: string | null = null;
        let inBracket = 0;
        for (let j = i + 9; j < src.length; j++) {
          const ch = src[j];
          if (inQuote) {
            if (ch === inQuote) inQuote = null;
          } else if (ch === '"' || ch === "'") {
            inQuote = ch;
          } else if (ch === '[') {
            inBracket++;
          } else if (ch === ']') {
            if (inBracket > 0) inBracket--;
          } else if (ch === '>' && inBracket === 0) {
            end = j;
            break;
          }
        }
        i = end === -1 ? src.length : end + 1;
        continue;
      }
      // 普通标签：扫描时跳过属性值内的 >，避免 <c r="A>B"> 被截断
      let end = -1;
      let inQuote: string | null = null;
      for (let j = i + 1; j < src.length; j++) {
        const ch = src[j];
        if (inQuote) {
          if (ch === inQuote) inQuote = null;
        } else if (ch === '"' || ch === "'") {
          inQuote = ch;
        } else if (ch === '>') {
          end = j;
          break;
        }
      }
      if (end === -1) break;
      const tag = src.slice(i + 1, end).trim();
      i = end + 1;

      if (tag.startsWith('?')) continue; // 跳过 XML 声明/PI
      if (tag.startsWith('/')) {
        // 闭合标签：仅当栈非空时弹出，避免多余闭合标签导致栈错乱
        if (stack.length > 1) stack.pop();
        continue;
      }

      const selfClose = tag.endsWith('/');
      const tagContent = selfClose ? tag.slice(0, -1).trim() : tag;
      const node = parseTagContent(tagContent);

      // 节点数上限守卫：防止恶意/损坏 XML 产生海量节点导致 OOM
      if (++nodeCount > MAX_XML_NODES) {
        throw new Error(`XML 节点数超限（${MAX_XML_NODES}），可能为恶意文件`);
      }

      const current = stack[stack.length - 1];
      if (current) current.children.push(node);
      if (!selfClose) {
        stack.push(node);
      }
    } else {
      // 文本内容
      const end = src.indexOf('<', i);
      const text = end === -1 ? src.slice(i) : src.slice(i, end);
      const decoded = decodeXmlEntities(text.trim());
      if (decoded) {
        const current = stack[stack.length - 1];
        if (current) current.text += decoded;
      }
      i = end === -1 ? src.length : end;
    }
  }

  return root.children[0] ?? root;
}

function parseTagContent(tagContent: string): XmlNode {
  const spaceIdx = tagContent.search(/\s/);
  const tag = spaceIdx === -1 ? tagContent : tagContent.slice(0, spaceIdx);
  const attrStr = spaceIdx === -1 ? '' : tagContent.slice(spaceIdx + 1);
  const attrs: Record<string, string> = {};

  // 解析属性 key="value" 或 key='value'，支持带命名空间前缀的属性名
  const attrRe = /([\w:]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
  let m: RegExpExecArray | null;
  while ((m = attrRe.exec(attrStr)) !== null) {
    const key = m[1].replace(/^\w+:/, ''); // 去属性命名空间前缀
    attrs[key] = decodeXmlEntities(m[2] ?? m[3] ?? '');
  }

  return { tag, attrs, text: '', children: [] };
}

/** 一次性解码 XML 实体，避免顺序替换导致 &amp;lt; 被错解为 < */
function decodeXmlEntities(s: string): string {
  const NAMED: Record<string, string> = {
    amp: '&', lt: '<', gt: '>', quot: '"', apos: "'",
  };
  return s.replace(/&(amp|lt|gt|quot|apos|#x[0-9a-fA-F]+|#\d+);/g, (whole, body: string) => {
    if (body[0] === '#') {
      const code = body[1] === 'x' || body[1] === 'X'
        ? parseInt(body.slice(2), 16)
        : parseInt(body.slice(1), 10);
      // 码点范围校验：XML 1.0 合法码点为 0x9/0xA/0xD/0x20-0xD7FF/0xE000-0xFFFD/0x10000-0x10FFFF，
      // 排除代理区 0xD800-0xD7FF 与 0xFFFE/0xFFFF，避免 fromCodePoint 抛 RangeError 或产出非法字符
      if (!isXmlCodePoint(code)) return whole;
      return String.fromCodePoint(code);
    }
    return NAMED[body] ?? whole;
  });
}

/** 判断码点是否为 XML 1.0 合法字符 */
function isXmlCodePoint(code: number): boolean {
  if (!Number.isFinite(code) || code < 0) return false;
  if (code === 0x9 || code === 0xA || code === 0xD) return true;
  if (code >= 0x20 && code <= 0xD7FF) return true;
  if (code >= 0xE000 && code <= 0xFFFD) return true;
  if (code >= 0x10000 && code <= 0x10FFFF) return true;
  return false;
}

/** 迭代查找第一个匹配 tag 的节点（显式栈，避免深嵌套 XML 栈溢出） */
export function findFirst(node: XmlNode, tag: string): XmlNode | null {
  const stack: XmlNode[] = [node];
  while (stack.length > 0) {
    const n = stack.pop()!;
    if (n.tag === tag) return n;
    // 逆序入栈保证按文档顺序遍历
    for (let i = n.children.length - 1; i >= 0; i--) {
      stack.push(n.children[i]);
    }
  }
  return null;
}

/** 查找所有匹配 tag 的节点（仅直接子节点） */
export function findAll(node: XmlNode, tag: string): XmlNode[] {
  return node.children.filter(c => c.tag === tag);
}

/** 迭代查找所有匹配 tag 的节点（显式栈，避免深嵌套 XML 栈溢出） */
export function findAllDeep(node: XmlNode, tag: string): XmlNode[] {
  const result: XmlNode[] = [];
  const stack: XmlNode[] = [node];
  while (stack.length > 0) {
    const n = stack.pop()!;
    if (n.tag === tag) result.push(n);
    for (let i = n.children.length - 1; i >= 0; i--) {
      stack.push(n.children[i]);
    }
  }
  return result;
}
