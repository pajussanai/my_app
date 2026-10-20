// Google Gemini API로 답변을 만든다(기본 제공자).
// SDK 없이 REST streamGenerateContent(alt=sse)를 직접 호출한다.
//
// 무료 할당량을 넘으면 Gemini가 429를 돌려준다. 이때 다시 시도하거나
// 다른(유료) 모델·제공자로 넘어가지 않고 ai_quota_exceeded 오류로 끝낸다.
import {
  AiError,
  buildTurns,
  type GeneratedReply,
  type GenerateOptions,
  replayableContent,
  SYSTEM_PROMPT,
} from "./ai.ts";

const API_BASE = "https://generativelanguage.googleapis.com/v1beta/models";
/** 무료 할당량 대상인 정식(stable) 모델. 서버 비밀값 GEMINI_MODEL로 바꿀 수 있다. */
export const DEFAULT_MODEL = "gemini-3.5-flash-lite";
/** 첫 응답이 올 때까지 기다리는 시간 */
const CONNECT_TIMEOUT_MS = 60_000;
const MODEL_RE = /^[a-z0-9][a-z0-9.\-]{0,99}$/;

type Part = Record<string, unknown>;

/** 답변을 거절한 것으로 보는 종료 사유 */
const BLOCKED_FINISH_REASONS = new Set([
  "SAFETY",
  "RECITATION",
  "BLOCKLIST",
  "PROHIBITED_CONTENT",
  "SPII",
  "IMAGE_SAFETY",
]);

/** HTTP 오류를 앱 오류 코드로 바꾼다. 응답 원문은 남기지 않는다. */
export function geminiHttpError(status: number, body: unknown): AiError {
  const error = (body as { error?: { status?: string; message?: string } })
    ?.error;
  if (status === 429 || status === 402) {
    // 무료 할당량(분당·일일) 초과. 유료로 넘어가지 않는다.
    return new AiError("ai_quota_exceeded");
  }
  if (
    status === 401 || status === 403 || status === 404 ||
    (status === 400 && /api key/i.test(error?.message ?? ""))
  ) {
    return new AiError("ai_not_configured");
  }
  if (status >= 500) return new AiError("ai_overloaded");
  return new AiError("ai_request_failed");
}

/** 스트림 조각마다 나뉘어 온 글 조각을 이어 붙여 저장할 블록으로 만든다. */
export function compactParts(parts: Part[]): Part[] {
  const out: Part[] = [];
  const plainText = (p: Part) =>
    typeof p.text === "string" && Object.keys(p).length === 1;
  for (const p of parts) {
    const last = out[out.length - 1];
    if (plainText(p) && last && plainText(last)) {
      last.text = String(last.text) + String(p.text);
    } else {
      out.push({ ...p });
    }
  }
  return out;
}

/** fetch 응답 본문에서 SSE의 data 줄을 하나씩 꺼낸다. */
async function* sseData(
  body: ReadableStream<Uint8Array>,
): AsyncGenerator<string> {
  const reader = body.pipeThrough(new TextDecoderStream()).getReader();
  let buffer = "";
  let data: string[] = [];
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += value;
    let newline: number;
    while ((newline = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, newline).replace(/\r$/, "");
      buffer = buffer.slice(newline + 1);
      if (line === "") {
        if (data.length > 0) yield data.join("\n");
        data = [];
      } else if (line.startsWith("data:")) {
        data.push(line.slice(5).trimStart());
      }
    }
  }
  if (data.length > 0) yield data.join("\n");
}

export function buildContents(
  history: GenerateOptions["history"],
  userText: string,
) {
  return buildTurns<Part>(
    history,
    userText,
    (m) => replayableContent(m, "gemini") ?? [{ text: m.content }],
  ).map((t) => ({
    role: t.role === "assistant" ? "model" : "user",
    parts: t.blocks,
  }));
}

export async function generateWithGemini(
  options: GenerateOptions,
): Promise<GeneratedReply> {
  const { apiKey, history, userText, signal, onText } = options;
  const model = Deno.env.get("GEMINI_MODEL") || DEFAULT_MODEL;
  if (!MODEL_RE.test(model)) throw new AiError("ai_not_configured");

  const connectTimeout = AbortSignal.timeout(CONNECT_TIMEOUT_MS);
  let response: Response;
  try {
    response = await fetch(
      `${API_BASE}/${model}:streamGenerateContent?alt=sse`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          // 키는 URL이 아니라 헤더로 보낸다(로그에 URL이 남아도 키는 남지 않게).
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
          contents: buildContents(history, userText),
          generationConfig: { maxOutputTokens: 8000 },
        }),
        signal: AbortSignal.any([signal, connectTimeout]),
      },
    );
  } catch {
    if (signal.aborted) throw new AiError("cancelled");
    if (connectTimeout.aborted) throw new AiError("timeout");
    throw new AiError("ai_unreachable");
  }

  if (!response.ok || !response.body) {
    const body = await response.json().catch(() => null);
    throw geminiHttpError(response.status, body);
  }

  const parts: Part[] = [];
  let text = "";
  let finishReason: string | null = null;
  let blocked = false;
  let usage: Record<string, number> = {};

  try {
    for await (const data of sseData(response.body)) {
      // deno-lint-ignore no-explicit-any
      let chunk: any;
      try {
        chunk = JSON.parse(data);
      } catch {
        throw new AiError("ai_request_failed");
      }
      if (chunk.error) {
        throw geminiHttpError(Number(chunk.error.code) || 500, chunk);
      }
      if (chunk.promptFeedback?.blockReason) blocked = true;
      if (chunk.usageMetadata) usage = chunk.usageMetadata;
      const candidate = chunk.candidates?.[0];
      if (!candidate) continue;
      if (candidate.finishReason) finishReason = candidate.finishReason;
      for (const part of (candidate.content?.parts ?? []) as Part[]) {
        parts.push(part);
        // 생각(thought) 조각은 화면에 보여 주지 않는다.
        if (typeof part.text === "string" && part.thought !== true) {
          text += part.text;
          onText(part.text);
        }
      }
    }
  } catch (error) {
    if (error instanceof AiError) throw error;
    if (signal.aborted) throw new AiError("cancelled");
    throw new AiError("ai_unreachable");
  }

  if (finishReason && BLOCKED_FINISH_REASONS.has(finishReason)) blocked = true;
  const cached = usage.cachedContentTokenCount ?? 0;
  return {
    text,
    apiContent: compactParts(parts),
    model,
    stopReason: finishReason?.toLowerCase() ?? null,
    refused: blocked,
    usage: {
      inputTokens: Math.max(0, (usage.promptTokenCount ?? 0) - cached),
      outputTokens: (usage.candidatesTokenCount ?? 0) +
        (usage.thoughtsTokenCount ?? 0),
      cacheReadTokens: cached,
      cacheCreationTokens: 0,
    },
  };
}
