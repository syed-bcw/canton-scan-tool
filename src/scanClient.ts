import https from "node:https";
import type { IncomingMessage } from "node:http";

export type ScanConfig = {
  scheme: "https";
  host: string; // TLS hostname + Host header
  port: number;
  ip: string; // where to connect (e.g. 127.0.0.1 for kubectl port-forward)
  prefix: string; // e.g. /api/scan
};

export function getDefaultScanConfig(env: NodeJS.ProcessEnv = process.env): ScanConfig {
  const host = env.SCAN_HOST ?? "scan.sv-1.global.canton.network.sync.global";
  const port = Number(env.SCAN_PORT ?? "3128");
  const ip = env.SCAN_IP ?? "127.0.0.1";
  const prefix = env.SCAN_PREFIX ?? "/api/scan";

  if (!Number.isFinite(port) || port <= 0) {
    throw new Error(`Invalid SCAN_PORT: ${env.SCAN_PORT}`);
  }

  return {
    scheme: "https",
    host,
    port,
    ip,
    prefix,
  };
}

function readJsonBody(res: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    res.on("data", (c: Buffer | string) => chunks.push(Buffer.isBuffer(c) ? c : Buffer.from(c)));
    res.on("end", () => {
      const body = Buffer.concat(chunks).toString("utf8");
      if (!body) return resolve(null);
      try {
        resolve(JSON.parse(body));
      } catch (err) {
        reject(new Error(`Failed to parse JSON (status=${res.statusCode}): ${String(err)}\nBody: ${body.slice(0, 2000)}`));
      }
    });
    res.on("error", reject);
  });
}

export async function scanPostJson<T>(
  cfg: ScanConfig,
  path: string,
  payload: unknown,
  extraHeaders: Record<string, string> = {}
): Promise<T> {
  const fullPath = `${cfg.prefix}${path}`;
  const body = JSON.stringify(payload);

  const headers: Record<string, string> = {
    Host: cfg.host,
    "Content-Type": "application/json",
    Accept: "application/json",
    "Content-Length": String(Buffer.byteLength(body)),
    ...extraHeaders,
  };

  return new Promise<T>((resolve, reject) => {
    const req = https.request(
      {
        host: cfg.ip,
        port: cfg.port,
        method: "POST",
        path: fullPath,
        servername: cfg.host, // SNI + cert validation
        headers,
      },
      async (res) => {
        try {
          const data = (await readJsonBody(res)) as T;
          const status = res.statusCode ?? 0;
          if (status < 200 || status >= 300) {
            reject(new Error(`HTTP ${status} for POST ${fullPath}: ${JSON.stringify(data).slice(0, 2000)}`));
            return;
          }
          resolve(data);
        } catch (err) {
          reject(err);
        }
      }
    );

    req.on("error", reject);
    req.write(body);
    req.end();
  });
}
