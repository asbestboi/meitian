import { SELF } from "cloudflare:test";

export const BASE = "https://meitian.test";

export async function call(method: string, path: string, token?: string, body?: unknown) {
  const headers: Record<string, string> = {};
  if (token) headers.authorization = `Bearer ${token}`;
  let payload: BodyInit | undefined;
  if (body instanceof Uint8Array) {
    payload = body;
    headers["content-type"] = "image/jpeg";
  } else if (body !== undefined) {
    payload = JSON.stringify(body);
    headers["content-type"] = "application/json";
  }
  const res = await SELF.fetch(BASE + path, { method, headers, body: payload });
  const type = res.headers.get("content-type") ?? "";
  return { status: res.status, data: type.includes("json") ? ((await res.json()) as any) : null, res };
}

let ip = 0;
export async function register(nickname: string) {
  const res = await SELF.fetch(BASE + "/v1/register", {
    method: "POST",
    headers: { "content-type": "application/json", "cf-connecting-ip": `10.0.0.${++ip}` },
    body: JSON.stringify({ nickname }),
  });
  const data = (await res.json()) as any;
  if (res.status !== 201) throw new Error(JSON.stringify(data));
  return data as { token: string; profile: any };
}

/** A WebSocket client with a queue of received messages. */
export async function socket(path: string, token: string) {
  const res = await SELF.fetch(BASE + path, { headers: { upgrade: "websocket", authorization: `Bearer ${token}` } });
  const ws = res.webSocket;
  if (!ws) throw new Error(`no websocket: ${res.status} ${await res.text()}`);
  ws.accept();
  const inbox: any[] = [];
  const waiters: (() => void)[] = [];
  let closed = false;
  ws.addEventListener("message", (e) => {
    try {
      inbox.push(JSON.parse(e.data as string));
    } catch {
      inbox.push(e.data);
    }
    waiters.splice(0).forEach((w) => w());
  });
  ws.addEventListener("close", () => {
    closed = true;
    waiters.splice(0).forEach((w) => w());
  });
  return {
    ws,
    inbox,
    get closed() {
      return closed;
    },
    send(msg: unknown) {
      ws.send(typeof msg === "string" ? msg : JSON.stringify(msg));
    },
    /** Waits for the first message (from the start of the inbox) matching `pred`, and removes it. */
    async next(pred: (m: any) => boolean = () => true, ms = 3000): Promise<any> {
      const end = Date.now() + ms;
      for (;;) {
        const i = inbox.findIndex(pred);
        if (i >= 0) return inbox.splice(i, 1)[0];
        if (Date.now() > end) throw new Error("timed out; inbox: " + JSON.stringify(inbox));
        await new Promise<void>((r) => {
          waiters.push(r);
          setTimeout(r, 50);
        });
      }
    },
  };
}
