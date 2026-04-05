import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const APK_DIR = path.join(__dirname, 'apk');
const PORT = process.env.APK_PORT || 3002;

function formatBytes(bytes) {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
  return (bytes / 1048576).toFixed(1) + ' MB';
}

function formatDate(mtime) {
  const d = new Date(mtime);
  const offset = 9 * 60; // JST
  const jst = new Date(d.getTime() + offset * 60000);
  return jst.toISOString().replace('T', ' ').slice(0, 19);
}

function getApkList() {
  if (!fs.existsSync(APK_DIR)) return [];
  return fs.readdirSync(APK_DIR)
    .filter(f => f.endsWith('.apk'))
    .map(f => {
      const stat = fs.statSync(path.join(APK_DIR, f));
      return { name: f, size: stat.size, mtime: stat.mtime };
    })
    .sort((a, b) => b.mtime - a.mtime);
}

function renderPage(apks) {
  const rows = apks.map(a => `
    <tr>
      <td><a href="/apk/${encodeURIComponent(a.name)}" style="color:#1a73e8;text-decoration:none;font-weight:500">${a.name}</a></td>
      <td style="text-align:right">${formatBytes(a.size)}</td>
      <td style="text-align:right">${formatDate(a.mtime)}</td>
    </tr>`).join('');

  return `<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>TailCall APK Download</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Segoe UI', Roboto, sans-serif; background: #f5f5f5; color: #333; padding: 16px; }
    .container { max-width: 700px; margin: 0 auto; }
    h1 { font-size: 20px; color: #1a73e8; margin-bottom: 8px; }
    .subtitle { font-size: 13px; color: #666; margin-bottom: 16px; }
    table { width: 100%; border-collapse: collapse; background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
    th, td { padding: 12px 16px; text-align: left; border-bottom: 1px solid #eee; font-size: 14px; }
    th { background: #1a73e8; color: #fff; font-weight: 500; }
    tr:hover { background: #f0f7ff; }
    .note { margin-top: 16px; padding: 12px; background: #fff3cd; border-radius: 6px; font-size: 12px; color: #856404; }
    .empty { text-align: center; padding: 40px; color: #999; }
  </style>
</head>
<body>
  <div class="container">
    <h1>TailCall APK</h1>
    <p class="subtitle">タップしてダウンロード → インストール</p>
    ${apks.length === 0
      ? '<div class="empty">APKファイルがありません</div>'
      : `<table>
          <tr><th>ファイル名</th><th style="text-align:right">サイズ</th><th style="text-align:right">更新日時</th></tr>
          ${rows}
        </table>`
    }
    <div class="note">
      ⚠️ インストールには「提供元不明のアプリ」の許可が必要です。<br>
      設定 → セキュリティ → 提供元不明のアプリ を有効にしてください。
    </div>
  </div>
</body>
</html>`;
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  // Health check
  if (url.pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', timestamp: new Date().toISOString() }));
    return;
  }

  // APK download
  if (url.pathname.startsWith('/apk/')) {
    const filename = path.basename(decodeURIComponent(url.pathname.slice(5)));
    if (!filename.endsWith('.apk')) {
      res.writeHead(400, { 'Content-Type': 'text/plain' });
      res.end('Invalid file type');
      return;
    }
    const filepath = path.join(APK_DIR, filename);
    if (!filepath.startsWith(APK_DIR) || !fs.existsSync(filepath)) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('File not found');
      return;
    }
    const stat = fs.statSync(filepath);
    console.log(`[${new Date().toISOString()}] Download: ${filename} (${formatBytes(stat.size)})`);
    res.writeHead(200, {
      'Content-Type': 'application/vnd.android.package-archive',
      'Content-Disposition': `attachment; filename="${filename}"`,
      'Content-Length': stat.size,
      'Cache-Control': 'no-store, no-cache, must-revalidate',
    });
    fs.createReadStream(filepath).pipe(res);
    return;
  }

  // APK list page
  if (url.pathname === '/' || url.pathname === '/apk') {
    const apks = getApkList();
    const html = renderPage(apks);
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not Found');
});

server.listen(PORT, () => {
  console.log(`TailCall APK Server running on http://localhost:${PORT}`);
  console.log(`APK directory: ${APK_DIR}`);
  const apks = getApkList();
  console.log(`APK files: ${apks.length}`);
});
