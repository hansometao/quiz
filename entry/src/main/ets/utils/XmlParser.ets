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

/**
 * 解析 XML 字符串为节点树
 */
export function parseXml(xml: string): XmlNode {
  // 去掉 XML 声明和命名空间前缀
  let src = xml
    .replace(/<\?xml[^>]*\?>/g, '')
    .replace(/\s+xmlns[^=]*="[^"]*"/g, '')
    .replace(/<(\/?)\w+:/g, '<$1');   // 去掉命名空间前缀如 <x:workbook>

  const root: XmlNode = { tag: 'root', attrs: {}, text: '', children: [] };
  const stack: XmlNode[] = [root];

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
      if (!isNaN(code) && code >= 0) return String.fromCodePoint(code);
      return whole;
    }
    return NAMED[body] ?? whole;
  });
}

/** 递归查找第一个匹配 tag 的节点 */
export function findFirst(node: XmlNode, tag: string): XmlNode | null {
  if (node.tag === tag) return node;
  for (const child of node.children) {
    const found = findFirst(child, tag);
    if (found) return found;
  }
  return null;
}

/** 查找所有匹配 tag 的节点（仅直接子节点） */
export function findAll(node: XmlNode, tag: string): XmlNode[] {
  return node.children.filter(c => c.tag === tag);
}

/** 递归查找所有匹配 tag 的节点 */
export function findAllDeep(node: XmlNode, tag: string): XmlNode[] {
  const result: XmlNode[] = [];
  const dfs = (n: XmlNode) => {
    if (n.tag === tag) result.push(n);
    n.children.forEach(dfs);
  };
  dfs(node);
  return result;
}
