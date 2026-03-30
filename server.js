const http = require("http");
const os = require("os");
const fs = require("fs");
const path = require("path");

const PORT = process.env.PORT || 8080;
const VERSION = process.env.APP_VERSION || "v1";
const COLOR = process.env.APP_COLOR || "#6366f1";

const html = fs.readFileSync(path.join(__dirname, "public", "index.html"), "utf8");

const server = http.createServer((req, res) => {
  const url = req.url;

  // Health check endpoint
  if (url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ status: "ok", version: VERSION }));
  }

  // Info API endpoint
  if (url === "/api/info") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(
      JSON.stringify({
        version: VERSION,
        color: COLOR,
        hostname: os.hostname(),
        platform: os.platform(),
        uptime: Math.floor(process.uptime()),
        timestamp: new Date().toISOString(),
        env: process.env.NODE_ENV || "production",
        port: PORT,
      })
    );
  }

  // Serve the HTML page
  const page = html
    .replace(/{{VERSION}}/g, VERSION)
    .replace(/{{COLOR}}/g, COLOR)
    .replace(/{{HOSTNAME}}/g, os.hostname());

  res.writeHead(200, { "Content-Type": "text/html" });
  res.end(page);
});

server.listen(PORT, () => {
  console.log(`GCP Demo App [${VERSION}] running on port ${PORT}`);
});
