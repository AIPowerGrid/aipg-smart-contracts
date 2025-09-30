const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

const COMFY_BASE = process.env.COMFY_BASE || 'http://172.30.30.122:8188';

function writeCORS(res) {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, Accept');
}

const server = http.createServer((req, res) => {
    // CORS preflight support
    writeCORS(res);
    if (req.method === 'OPTIONS') {
        res.writeHead(204);
        return res.end();
    }

    // Simple proxy for ComfyUI to avoid browser CORS issues
    if (req.url.startsWith('/comfy')) {
        const suffix = req.url === '/comfy' ? '/' : req.url.replace('/comfy', '');
        const targetUrl = new URL(suffix, COMFY_BASE);
        const isPost = req.method === 'POST';
        const proxyReq = http.request({
            method: req.method,
            hostname: targetUrl.hostname,
            port: targetUrl.port || 80,
            path: targetUrl.pathname + targetUrl.search,
            headers: {
                'Content-Type': req.headers['content-type'] || 'application/json'
            }
        }, (proxyRes) => {
            let chunks = [];
            proxyRes.on('data', (d) => chunks.push(d));
            proxyRes.on('end', () => {
                writeCORS(res);
                res.writeHead(proxyRes.statusCode || 500, { 'Content-Type': proxyRes.headers['content-type'] || 'application/json' });
                res.end(Buffer.concat(chunks));
            });
        });
        proxyReq.on('error', (e) => {
            writeCORS(res);
            res.writeHead(502, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Proxy error', details: e.message }));
        });
        if (isPost) {
            let body = [];
            req.on('data', (chunk) => body.push(chunk));
            req.on('end', () => {
                proxyReq.end(Buffer.concat(body));
            });
        } else {
            proxyReq.end();
        }
        return;
    }
    let filePath = '.' + req.url;
    if (filePath === './') {
        filePath = './index.html';
    }

    const extname = String(path.extname(filePath)).toLowerCase();
    const mimeTypes = {
        '.html': 'text/html',
        '.js': 'text/javascript',
        '.css': 'text/css',
        '.json': 'application/json',
        '.png': 'image/png',
        '.jpg': 'image/jpg',
        '.gif': 'image/gif',
        '.svg': 'image/svg+xml',
        '.wav': 'audio/wav',
        '.mp4': 'video/mp4',
        '.woff': 'application/font-woff',
        '.ttf': 'application/font-ttf',
        '.eot': 'application/vnd.ms-fontobject',
        '.otf': 'application/font-otf',
        '.wasm': 'application/wasm'
    };

    const contentType = mimeTypes[extname] || 'application/octet-stream';

    fs.readFile(filePath, (error, content) => {
        if (error) {
            if (error.code === 'ENOENT') {
                res.writeHead(404, { 'Content-Type': 'text/html' });
                res.end('<h1>404 Not Found</h1>', 'utf-8');
            } else {
                res.writeHead(500);
                res.end(`Server Error: ${error.code}`);
            }
        } else {
            writeCORS(res);
            res.writeHead(200, { 'Content-Type': contentType });
            res.end(content, 'utf-8');
        }
    });
});

const PORT = process.env.PORT || 8000;
server.listen(PORT, () => {
    console.log(`🚀 AIPG NFT Generator Frontend running at http://localhost:${PORT}`);
    console.log(`📱 Open in your browser and connect MetaMask to Base Sepolia`);
    console.log(`🎨 Uses ComfyUI for image generation`);
});

