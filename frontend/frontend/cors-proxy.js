const http = require('http');
const https = require('https');
const url = require('url');

const COMFYUI_HOST = '172.30.30.122';
const COMFYUI_PORT = 8188;
const PROXY_PORT = 8001;

const server = http.createServer((req, res) => {
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, Client-Agent');
  
  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }
  
  // Parse the request URL
  const parsedUrl = url.parse(req.url, true);
  const path = parsedUrl.pathname;
  const query = parsedUrl.query;
  
  // Build the target URL
  const targetUrl = `http://${COMFYUI_HOST}:${COMFYUI_PORT}${path}${query ? '?' + new URLSearchParams(query).toString() : ''}`;
  
  console.log(`Proxying ${req.method} ${req.url} -> ${targetUrl}`);
  
  // Forward the request to ComfyUI
  const options = {
    hostname: COMFYUI_HOST,
    port: COMFYUI_PORT,
    path: path + (query ? '?' + new URLSearchParams(query).toString() : ''),
    method: req.method,
    headers: {
      ...req.headers,
      host: `${COMFYUI_HOST}:${COMFYUI_PORT}`
    }
  };
  
  const proxyReq = http.request(options, (proxyRes) => {
    // Forward response headers
    Object.keys(proxyRes.headers).forEach(key => {
      res.setHeader(key, proxyRes.headers[key]);
    });
    
    // Set CORS headers again for the response
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, Client-Agent');
    
    res.writeHead(proxyRes.statusCode);
    proxyRes.pipe(res);
  });
  
  proxyReq.on('error', (err) => {
    console.error('Proxy error:', err);
    res.writeHead(500);
    res.end('Proxy error: ' + err.message);
  });
  
  // Forward request body
  req.pipe(proxyReq);
});

server.listen(PROXY_PORT, () => {
  console.log(`🚀 CORS Proxy running on port ${PROXY_PORT}`);
  console.log(`📡 Proxying to ComfyUI at ${COMFYUI_HOST}:${COMFYUI_PORT}`);
  console.log(`🌐 Frontend can now use: http://localhost:${PROXY_PORT}`);
});
