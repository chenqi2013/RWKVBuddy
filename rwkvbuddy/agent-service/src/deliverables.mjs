import { mkdir, mkdtemp, writeFile, rename, rm } from 'node:fs/promises';
import { join, extname } from 'node:path';
import { randomUUID, createHash } from 'node:crypto';
import { Document, Packer, Paragraph, HeadingLevel } from 'docx';
import ExcelJS from 'exceljs';
import { checkAbort } from './runtime.mjs';

export const deliveryInstruction = `除回答外，如用户要求生成、修改、翻译或整理成文件，必须返回 files 数组（最多 6 个）。
文件均为新副本，不能声称覆盖原件。只根据实际读取的内容生成，不虚构未读取部分已修改，也不能用省略号代替用户要求的完整正文。
格式：{"answer":"Markdown 中文回答","files":[{"name":"成果.docx","content":"完整正文，使用换行分段"}]}。
支持 .docx、.md、.txt、.csv、.json；这些格式使用 content 字符串，.json 必须为有效 JSON。
.xlsx 必须使用 sheets 工作表数组，完整响应示例：{"answer":"已提交 Excel 数据，程序将生成文件。","files":[{"name":"结果.xlsx","sheets":[{"name":"数据","rows":[["项目","金额"],["示例",100]]}]}]}。
Excel 必须有 1–8 个工作表，每个工作表提供 name 和 rows 二维数组；单元格只允许文字、数字、布尔值或 null。不得使用 content 中的 Markdown 表格、CSV 或普通文字冒充 .xlsx。
不要返回文件路径或下载链接，程序会实际生成文件并展示下载按钮。未要求文件时 files=[]。
你只需提交结构化文件数据，由本机工具写入文件；不要声称环境无法生成或下载文件，也不要让用户把文字自行另存为 .xlsx。
DOCX/XLSX 根据提取内容重新生成，不保留原件复杂排版、公式和图表，回答须说明相关局限。`;

function validate(specs) {
  if (!Array.isArray(specs) || specs.length > 6) throw new Error('每次最多生成 6 个文件');
  if (JSON.stringify(specs).length > 120000) throw new Error('生成文件内容超过单次上限，请拆分任务');
  const names = new Set();
  return specs.map((spec) => {
    if (!spec || typeof spec.name !== 'string' || spec.name.length > 120 ||
        /[\\/<>:"|?*\x00-\x1f]/.test(spec.name) || spec.name.startsWith('.') || /[. ]$/.test(spec.name) ||
        /^(con|prn|aux|nul|com[1-9]|lpt[1-9])\./i.test(spec.name)) throw new Error('成果文件名无效，请使用普通文件名');
    const name = spec.name.normalize('NFC');
    if (names.has(name.toLowerCase())) throw new Error('成果文件名不能重复');
    names.add(name.toLowerCase());
    const extension = extname(name).toLowerCase();
    if (!['.docx', '.xlsx', '.md', '.txt', '.csv', '.json'].includes(extension)) throw new Error('生成格式仅支持 DOCX、XLSX、Markdown、TXT、CSV、JSON');
    if (extension !== '.xlsx') {
      if (typeof spec.content !== 'string' || !spec.content.trim() || spec.content.length > 60000 ||
          /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(spec.content)) throw new Error('成果缺少有效的完整文本内容');
      if (extension === '.json') { try { JSON.parse(spec.content); } catch { throw new Error('生成的 JSON 文件格式无效'); } }
      return { name, extension, content: spec.content };
    }
    if (!Array.isArray(spec.sheets) || !spec.sheets.length || spec.sheets.length > 8) throw new Error(`${name}：工作簿需要 1–8 个工作表，请提供 sheets 数组，每项为 {name, rows}；.xlsx 不能使用 content 文本代替工作表`);
    const sheetNames = new Set();
    let cells = 0;
    for (const sheet of spec.sheets) {
      if (!sheet || typeof sheet.name !== 'string' || !sheet.name.trim() || sheet.name.length > 31 ||
          /[\\/\[\]:?*\x00-\x1f]/.test(sheet.name) || /^'|'$/.test(sheet.name) || sheetNames.has(sheet.name.toLowerCase())) throw new Error('工作表名称无效或重复');
      sheetNames.add(sheet.name.toLowerCase());
      if (!Array.isArray(sheet.rows) || !sheet.rows.length || sheet.rows.length > 1000) throw new Error('每张工作表需要 1–1000 行');
      for (const row of sheet.rows) {
        if (!Array.isArray(row) || row.length > 100 || (cells += row.length) > 5000 ||
            row.some((cell) => cell !== null && !['string', 'number', 'boolean'].includes(typeof cell) ||
              typeof cell === 'number' && !Number.isFinite(cell) || typeof cell === 'string' && (cell.length > 10000 || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(cell)))) throw new Error('工作表单元格格式无效或超过 5000 格上限');
      }
    }
    return { name, extension, sheets: spec.sheets };
  });
}

export async function createDeliverables(specs, directory, signal) {
  checkAbort(signal);
  let files;
  try { files = validate(specs); }
  catch (error) { error.code = 'DELIVERY_INVALID_SPEC'; throw error; }
  if (!files.length) return { files: [], texts: {} };
  checkAbort(signal);
  await mkdir(directory, { recursive: true });
  const staging = await mkdtemp(join(directory, '.outputs-'));
  const results = [];
  const texts = {};
  try {
    for (const spec of files) {
      checkAbort(signal);
      let bytes;
      let text = spec.content;
      if (spec.extension === '.docx') {
        const children = text.split(/\r?\n/).map((line) => {
          const heading = line.match(/^(#{1,3})\s+(.*)/);
          return new Paragraph({ text: heading ? heading[2] : line,
            ...(heading ? { heading: [HeadingLevel.HEADING_1, HeadingLevel.HEADING_2, HeadingLevel.HEADING_3][heading[1].length - 1] } : {}) });
        });
        bytes = await Packer.toBuffer(new Document({ sections: [{ children }] }));
      } else if (spec.extension === '.xlsx') {
        const workbook = new ExcelJS.Workbook();
        for (const sheet of spec.sheets) {
          const worksheet = workbook.addWorksheet(sheet.name);
          worksheet.addRows(sheet.rows);
          worksheet.getRow(1).font = { bold: true };
          worksheet.views = [{ state: 'frozen', ySplit: 1 }];
          worksheet.columns.forEach((column) => { column.width = 24; column.alignment = { vertical: 'top', wrapText: true }; });
        }
        bytes = Buffer.from(await workbook.xlsx.writeBuffer());
        text = spec.sheets.map((sheet) => `[工作表：${sheet.name}]\n${sheet.rows.map((row) => row.map((cell) => cell ?? '').join('\t')).join('\n')}`).join('\n\n');
      } else { bytes = Buffer.from(text, 'utf8'); }
      if (bytes.length > 2 * 1024 * 1024) throw new Error('单个成果文件超过 2 MB 上限');
      await writeFile(join(staging, spec.name), bytes, { flag: 'wx' });
      results.push({ id: randomUUID(), name: spec.name, format: spec.extension.slice(1), bytes: bytes.length,
        hash: createHash('sha256').update(bytes).digest('hex'), path: join(directory, 'outputs', spec.name) });
      texts[spec.name] = text;
    }
    checkAbort(signal);
    await rename(staging, join(directory, 'outputs'));
    return { files: results, texts };
  } catch (error) { await rm(staging, { recursive: true, force: true }); throw error; }
}
