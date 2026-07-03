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
      // 找到标签结束
      const end = src.indexOf('>', i);
      if (end === -1) break;
      const tag = src.slice(i + 1, end).trim();
      i = end + 1;

      if (tag.startsWith('?')) continue; // 跳过 XML 声明/PI（如 <?xml ...?>）
      if (tag.startsWith('!')) {
        // 处理 CDATA: <![CDATA[内容]]>
        const cdataMatch = tag.match(/^!\[CDATA\[([\s\S]*?)\]\]$/);
        if (cdataMatch) {
          const current = stack[stack.length - 1];
          current.text += cdataMatch[1];
        }
        continue; // 跳过普通注释 <!--...-->
      }
      if (tag.startsWith('/')) {
        // 闭合标签
        stack.pop();
        continue;
      }

      const selfClose = tag.endsWith('/');
      const tagContent = selfClose ? tag.slice(0, -1).trim() : tag;
      const node = parseTagContent(tagContent);

      const current = stack[stack.length - 1];
      current.children.push(node);
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
        current.text += decoded;
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

  // 解析属性 key="value"
  const attrRe = /(\w+)\s*=\s*"([^"]*)"/g;
  let m: RegExpExecArray | null;
  while ((m = attrRe.exec(attrStr)) !== null) {
    attrs[m[1]] = decodeXmlEntities(m[2]);
  }

  return { tag, attrs, text: '', children: [] };
}

function decodeXmlEntities(s: string): string {
  return s
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)));
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
