import { parentPort, workerData } from 'node:worker_threads';
import { unzipSync } from 'fflate';
import { XMLParser, XMLValidator } from 'fast-xml-parser';

const limit = 1024 * 1024;
const array = (value) => value == null ? [] : Array.isArray(value) ? value : [value];
const text = (value) => value == null ? '' : typeof value === 'object'
  ? Object.entries(value).filter(([key]) => !key.startsWith('@_')).map(([, item]) => array(item).map(text).join('')).join('')
  : String(value);
function xml(source, ordered = false) {
  if (/<!DOCTYPE|<!ENTITY/i.test(source)) throw new Error('文档包含不支持的 XML 声明');
  if (XMLValidator.validate(source) !== true) throw new Error('文档 XML 已损坏，请重新保存后重试');
  return new XMLParser({ ignoreAttributes: false, removeNSPrefix: true, parseTagValue: false,
    trimValues: false, preserveOrder: ordered }).parse(source);
}
function office(bytes) {
  let expanded = 0;
  return unzipSync(bytes, { filter: (file) => {
    if (!/^(word\/document\.xml|xl\/(workbook\.xml|_rels\/workbook\.xml\.rels|sharedStrings\.xml|worksheets\/sheet\d+\.xml))$/.test(file.name)) return false;
    expanded += file.originalSize;
    if (file.originalSize > 8 * 1024 * 1024 || expanded > 24 * 1024 * 1024) throw new Error('文档解压后超过读取上限');
    return true;
  } });
}
const decode = (bytes) => new TextDecoder('utf-8', { fatal: true }).decode(bytes);
function docx(bytes) {
  const files = office(bytes);
  if (!files['word/document.xml']) throw new Error('不是有效的 DOCX 文档');
  function walk(nodes) {
    return array(nodes).map((node) => Object.entries(node).map(([key, value]) => {
      if (key === '#text') return String(value);
      if (key === 'tab') return '\t';
      if (key === 'br' || key === 'cr') return '\n';
      if (key.startsWith(':') || key === 'instrText' || key === 'del') return '';
      return walk(value) + (key === 'p' || key === 'tr' ? '\n' : key === 'tc' ? '\t' : '');
    }).join('')).join('');
  }
  return { content: walk(xml(decode(files['word/document.xml']), true)), warnings: ['DOCX 已提取正文和表格文字；图片、批注、页眉页脚未纳入。'] };
}
function xlsx(bytes) {
  const files = office(bytes);
  const read = (name) => files[name] ? xml(decode(files[name])) : null;
  const workbook = read('xl/workbook.xml');
  if (!workbook?.workbook) throw new Error('不是有效的 XLSX 工作簿');
  const strings = array(read('xl/sharedStrings.xml')?.sst?.si).map(text);
  const relationships = array(read('xl/_rels/workbook.xml.rels')?.Relationships?.Relationship);
  const lines = [];
  let cells = 0;
  let size = 0;
  for (const sheet of array(workbook.workbook.sheets?.sheet)) {
    const rel = relationships.find((item) => item['@_Id'] === sheet['@_id']);
    const target = rel?.['@_Target']?.replace(/^\//, '');
    const path = target?.startsWith('xl/') ? target : `xl/${target}`;
    const data = read(path);
    if (!data?.worksheet) throw new Error(`无法读取工作表 ${sheet['@_name'] || ''}`);
    lines.push(`[工作表：${sheet['@_name'] || path}]`);
    for (const row of array(data.worksheet.sheetData?.row)) {
      const values = array(row.c).map((cell) => {
        if (++cells > 50000) throw new Error('工作簿超过 50000 个单元格，请拆分后重试');
        const value = cell['@_t'] === 's' ? strings[Number(text(cell.v))] ?? ''
          : cell['@_t'] === 'inlineStr' ? text(cell.is) : text(cell.v);
        const result = `${cell['@_r'] || '?'}=${cell.f ? `=${text(cell.f)} [缓存值：${value || '无'}]` : value}`;
        size += result.length;
        if (size > limit) throw new Error('工作簿提取文本超过 1 MB，请拆分后重试');
        return result;
      });
      if (values.length) lines.push(values.join('\t'));
    }
  }
  return { content: lines.join('\n'), warnings: ['XLSX 已提取工作表单元格；公式仅显示公式及文件内缓存值，未重算，日期可能显示为原始序列值。图表、图片未纳入。'] };
}
async function pdf(bytes) {
  // PDF.js warnings must never pollute the service's JSONL stdout.
  console.log = console.warn = () => {};
  const { getDocument } = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const task = getDocument({ data: bytes, isEvalSupported: false, useSystemFonts: true, verbosity: 0 });
  try {
    const document = await task.promise;
    const pages = [];
    let size = 0;
    for (let i = 1; i <= Math.min(document.numPages, 100); i++) {
      const page = await document.getPage(i);
      const items = await page.getTextContent();
      const content = items.items.map((item) => (item.str || '') + (item.hasEOL ? '\n' : ' ')).join('');
      size += content.length;
      if (size > limit) throw new Error('PDF 提取文本超过 1 MB，请拆分后重试');
      pages.push(`[第 ${i} 页]\n${content}`);
      page.cleanup();
    }
    if (!pages.some((page) => page.replace(/^\[第 \d+ 页\]/, '').trim())) throw new Error('PDF 无可提取文字，扫描件需先进行 OCR');
    return { content: pages.join('\n\n'), warnings: [
      'PDF 按页提取文字，未进行 OCR，表格布局和图片信息可能缺失。',
      ...(document.numPages > 100 ? [`PDF 共 ${document.numPages} 页，仅提取前 100 页。`] : []),
    ] };
  } catch (error) {
    if (error.name === 'PasswordException') throw new Error('PDF 已加密，请先解密后重试');
    throw error;
  } finally { await task.destroy(); }
}
try {
  const bytes = new Uint8Array(workerData.bytes);
  const result = workerData.extension === '.pdf' ? await pdf(bytes)
    : workerData.extension === '.docx' ? docx(bytes) : xlsx(bytes);
  if (!result.content.trim()) throw new Error('文件没有可分析的文字');
  if (Buffer.byteLength(result.content, 'utf8') > limit) throw new Error('提取文本超过 1 MB，请拆分后重试');
  parentPort.postMessage(result);
} catch (error) { parentPort.postMessage({ error: error.message }); }
