// Edge Function "chat": 로그인한 사용자의 질문에 AI 답변을 스트리밍으로 보내고,
// 답변이 끝나면 질문과 답변을 서버에서 함께 저장한다.
//
// 요청: POST { conversation_id, content }  (Authorization: Bearer <사용자 JWT>)
//       GET  → 오늘의 사용량 JSON(앱이 집계한 값. Google 무료 잔여량이 아니다)
// 응답: 검사 실패 → JSON 오류(4xx/5xx)
//       검사 통과 → text/event-stream
//         event: delta  data: {"text": "..."}       답변 글 조각
//         event: reset  data: {}                     지금까지의 글을 버리고 다시 시작
//         event: done   data: {"user_message", "assistant_message"}  저장 완료
//         event: error  data: {"code": "..."}        실패(아무것도 저장되지 않음)
//
// 비밀값(GEMINI_API_KEY 등 AI 키, service role 키)은 서버 환경 변수로만 읽고,
// 로그에는 오류 코드만 남긴다(질문·답변 내용과 토큰은 남기지 않는다).
// AI 제공자 선택은 providers.ts 참고(기본 gemini, AI_PROVIDER=claude로 되돌릴 수 있다).
import { createClient } from "@supabase/supabase-js";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { AiError, type AiProvider } from "./ai.ts";
import { aiConfig, currentModel, generateReply } from "./providers.ts";
import {
  dailyLimitReached,
  usageToday,
  loadHistory,
  ownsConversation,
  recordUsage,
  saveExchange,
  StoreError,
} from "./store.ts";

const MAX_CONTENT_LENGTH = 4000;
/** AI 답변 전체에 허용하는 시간 */
const REPLY_DEADLINE_MS = 120_000;
/** 답변을 생각하는 동안 연결이 끊기지 않도록 보내는 신호 간격 */
const PING_INTERVAL_MS = 15_000;
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function defaultDailyLimit(): number {
  const value = Number(Deno.env.get("CHAT_DAILY_LIMIT") ?? "100");
  return Number.isInteger(value) && value >= 0 ? value : 100;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST" && req.method !== "GET") {
    return jsonResponse(405, { code: "method_not_allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    console.error("chat: server_misconfigured");
    return jsonResponse(500, { code: "server_misconfigured" });
  }
  const db = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1. 로그인 확인: Authorization 헤더의 JWT를 Supabase Auth로 검증한다.
  const token = req.headers.get("Authorization")?.match(/^Bearer\s+(.+)$/i)
    ?.[1];
  if (!token) return jsonResponse(401, { code: "unauthorized" });
  const { data: auth, error: authError } = await db.auth.getUser(token);
  if (authError || !auth?.user) {
    return jsonResponse(401, { code: "unauthorized" });
  }
  const userId = auth.user.id;

  // GET: 오늘의 사용량(앱 집계). AI는 호출하지 않는다.
  if (req.method === "GET") return usageResponse(db, userId);

  // 2. 요청 내용 확인
  let body: { conversation_id?: unknown; content?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { code: "invalid_request" });
  }
  const conversationId = body.conversation_id;
  const content = body.content;
  if (
    typeof conversationId !== "string" || !UUID_RE.test(conversationId) ||
    typeof content !== "string" || content.trim().length === 0 ||
    content.length > MAX_CONTENT_LENGTH
  ) {
    return jsonResponse(400, { code: "invalid_request" });
  }

  try {
    // 3. 이 사용자의 대화인지 서버에서 확인
    if (!(await ownsConversation(db, userId, conversationId))) {
      return jsonResponse(404, { code: "conversation_not_found" });
    }

    // 4. AI 키가 서버 비밀값으로 등록되어 있는지
    const ai = aiConfig();
    if (!ai) {
      console.error("chat: ai_not_configured");
      return jsonResponse(503, { code: "ai_not_configured" });
    }

    // 5. 하루 사용 한도
    if (await dailyLimitReached(db, userId, defaultDailyLimit())) {
      return jsonResponse(429, { code: "daily_limit_reached" });
    }

    const history = await loadHistory(db, userId, conversationId);
    return streamReply({
      db,
      ...ai,
      userId,
      conversationId,
      userText: content,
      history,
      requestSignal: req.signal,
    });
  } catch (error) {
    const code = error instanceof StoreError ? error.code : "internal_error";
    console.error(`chat: ${code}`);
    return jsonResponse(500, { code });
  }
});

function streamReply(input: {
  db: ReturnType<typeof createClient>;
  provider: AiProvider;
  apiKey: string;
  userId: string;
  conversationId: string;
  userText: string;
  history: Awaited<ReturnType<typeof loadHistory>>;
  requestSignal: AbortSignal;
}): Response {
  const { db, provider, apiKey, userId, conversationId, userText, history } =
    input;
  const encoder = new TextEncoder();
  const abort = new AbortController();
  let timedOut = false;
  let closed = false;

  // 앱이 연결을 끊으면 AI 호출도 멈춘다(비용 절약).
  input.requestSignal.addEventListener("abort", () => abort.abort());

  const body = new ReadableStream<Uint8Array>({
    async start(controller) {
      const send = (event: string, data: Record<string, unknown>) => {
        if (closed) return;
        try {
          controller.enqueue(
            encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`),
          );
        } catch {
          closed = true;
        }
      };
      const ping = setInterval(() => {
        if (closed) return;
        try {
          controller.enqueue(encoder.encode(": ping\n\n"));
        } catch {
          closed = true;
        }
      }, PING_INTERVAL_MS);
      const deadline = setTimeout(() => {
        timedOut = true;
        abort.abort();
      }, REPLY_DEADLINE_MS);

      try {
        // AI 생성 (저장과 분리)
        const reply = await generateReply(provider, {
          apiKey,
          history,
          userText,
          signal: abort.signal,
          onText: (text) => send("delta", { text }),
          onRestart: () => send("reset", {}),
        });

        if (reply.refused || reply.text.trim().length === 0) {
          // 토큰은 썼으므로 사용량은 기록하되, 거절되거나 빈 답변은 저장하지 않는다.
          await recordUsage(db, userId, reply.usage).catch(() => {
            console.error("chat: usage_failed");
          });
          const code = reply.refused ? "refused" : "empty_reply";
          console.error(`chat: ${code}`);
          // 거절 전에 보낸 글 조각은 화면에서 지운다.
          if (reply.text.length > 0) send("reset", {});
          send("error", { code });
          return;
        }

        // 생성이 끝난 뒤에만 저장한다. 실패하면 done을 보내지 않는다.
        const saved = await saveExchange(db, {
          userId,
          conversationId,
          userText,
          reply,
        });
        await recordUsage(db, userId, reply.usage).catch(() => {
          // 답변은 이미 저장됐으므로 사용자에게는 성공으로 보낸다.
          console.error("chat: usage_failed");
        });
        send("done", { ...saved });
      } catch (error) {
        let code = "internal_error";
        if (error instanceof AiError) code = error.code;
        if (error instanceof StoreError) code = error.code;
        if (timedOut) code = "timeout";
        console.error(`chat: ${code}`);
        send("error", { code });
      } finally {
        clearInterval(ping);
        clearTimeout(deadline);
        if (!closed) {
          closed = true;
          try {
            controller.close();
          } catch {
            // 이미 닫힘
          }
        }
      }
    },
    cancel() {
      closed = true;
      abort.abort();
    },
  });

  return new Response(body, {
    headers: {
      ...corsHeaders,
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache",
      "X-Accel-Buffering": "no",
    },
  });
}

/**
 * 오늘의 사용량. usage_daily(서버가 기록)와 앱 일일 한도만 알려 준다.
 * Google Gemini 무료 할당량의 잔여량은 API로 알 수 없으므로 담지 않는다.
 */
async function usageResponse(
  db: ReturnType<typeof createClient>,
  userId: string,
): Promise<Response> {
  try {
    const usage = await usageToday(db, userId, defaultDailyLimit());
    const { provider, model } = currentModel();
    return jsonResponse(200, {
      day: usage.day,
      provider,
      model,
      ai_configured: aiConfig() !== null,
      request_count: usage.requestCount,
      input_tokens: usage.inputTokens + usage.cacheReadTokens,
      output_tokens: usage.outputTokens,
      daily_limit: usage.dailyLimit,
      remaining: Math.max(0, usage.dailyLimit - usage.requestCount),
    });
  } catch (error) {
    const code = error instanceof StoreError ? error.code : "internal_error";
    console.error(`chat: ${code}`);
    return jsonResponse(500, { code });
  }
}
