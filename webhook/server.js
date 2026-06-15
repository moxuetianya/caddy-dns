const http = require("http");
const crypto = require("crypto");
const { exec } = require("child_process");

const PORT = parseInt(process.env.WEBHOOK_PORT || "9000", 10);
const SECRET = process.env.WEBHOOK_SECRET || "";
const DEPLOY_SCRIPT = process.env.DEPLOY_SCRIPT || __dirname + "/deploy.sh";

function verifySignature(payload, signature) {
  if (!SECRET) return true;
  if (!signature) return false;
  const hmac = crypto.createHmac("sha256", SECRET);
  hmac.update(payload);
  const digest = "sha256=" + hmac.digest("hex");
  try {
    return crypto.timingSafeEqual(Buffer.from(digest), Buffer.from(signature));
  } catch {
    return false;
  }
}

function runDeploy(res) {
  exec(`bash "${DEPLOY_SCRIPT}"`, { timeout: 300000 }, (err, stdout, stderr) => {
    if (err) {
      console.error("Deploy failed:", err.message);
      if (stderr) console.error(stderr);
      if (!res.headersSent) {
        res.writeHead(500);
        res.end("Deploy failed: " + err.message);
      }
      return;
    }
    console.log(stdout);
    if (!res.headersSent) {
      res.writeHead(200);
      res.end("OK");
    }
  });
}

const server = http.createServer((req, res) => {
  if (req.method !== "POST" || req.url !== "/webhook") {
    res.writeHead(404);
    res.end("Not Found");
    return;
  }

  let body = [];
  req.on("data", (chunk) => body.push(chunk));
  req.on("end", () => {
    const raw = Buffer.concat(body);
    const signature = req.headers["x-hub-signature-256"];

    if (!verifySignature(raw, signature)) {
      res.writeHead(403);
      res.end("Forbidden");
      return;
    }

    try {
      const event = req.headers["x-github-event"] || "";
      const payload = JSON.parse(raw.toString());
      const ref = payload.ref || "";
      console.log(`[${new Date().toISOString()}] event=${event} ref=${ref}`);
    } catch {
      // 非 JSON 请求也放行（测试用）
    }

    // 立即返回 200，后台执行部署
    res.writeHead(200);
    res.end("Accepted");
    runDeploy(res);
  });
});

server.listen(PORT, () => {
  console.log(`Webhook listening on port ${PORT}`);
  if (!SECRET) console.warn("WARNING: WEBHOOK_SECRET not set, signature verification disabled");
});
