// DB 읽기·쓰기만 담당한다(AI는 다루지 않는다).
// service_role 클라이언트를 쓰므로 RLS가 적용되지 않는다.
// 그래서 모든 조회·저장에 user_id 조건을 직접 넣는다.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { HistoryMessage } from "./ai.ts";

/** 이전 대화를 몇 개까지 AI에 보낼지 */
const HISTORY_LIMIT = 40;

export class StoreError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

/** 이 사용자의 대화가 맞는지 확인한다. */
export async function ownsConversation(
  db: SupabaseClient,
  userId: string,
  conversationId: string,
): Promise<boolean> {
  const { data, error } = await db
    .from("conversations")
    .select("id")
    .eq("id", conversationId)
    .eq("user_id", userId)
    .maybeSingle();
  if (error) throw new StoreError("db_error");
  return data !== null;
}

/** 한국 시간 기준 오늘 날짜(YYYY-MM-DD). record_usage()와 같은 기준. */
export function seoulToday(now = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Seoul",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

/** 앱이 집계한 오늘 사용량과 앱 일일 한도(Google 무료 할당량과는 별개) */
export interface UsageToday {
  day: string;
  requestCount: number;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  dailyLimit: number;
}

/** 오늘 사용량. 사용자별 한도가 없으면 기본 한도를 쓴다. */
export async function usageToday(
  db: SupabaseClient,
  userId: string,
  defaultLimit: number,
): Promise<UsageToday> {
  const day = seoulToday();
  const [settings, usage] = await Promise.all([
    db.from("user_settings").select("daily_message_limit").eq(
      "user_id",
      userId,
    ).maybeSingle(),
    db.from("usage_daily")
      .select("request_count, input_tokens, output_tokens, cache_read_tokens")
      .eq("user_id", userId)
      .eq("day", day)
      .maybeSingle(),
  ]);
  if (settings.error || usage.error) throw new StoreError("db_error");
  return {
    day,
    requestCount: usage.data?.request_count ?? 0,
    // bigint 컬럼은 문자열로 올 수 있어 숫자로 바꾼다.
    inputTokens: Number(usage.data?.input_tokens ?? 0),
    outputTokens: Number(usage.data?.output_tokens ?? 0),
    cacheReadTokens: Number(usage.data?.cache_read_tokens ?? 0),
    dailyLimit: settings.data?.daily_message_limit ?? defaultLimit,
  };
}

/** 오늘 앱 한도에 도달했는지 */
export async function dailyLimitReached(
  db: SupabaseClient,
  userId: string,
  defaultLimit: number,
): Promise<boolean> {
  const usage = await usageToday(db, userId, defaultLimit);
  return usage.requestCount >= usage.dailyLimit;
}

/** 최근 완료된 메시지를 오래된 순서로 가져온다. */
export async function loadHistory(
  db: SupabaseClient,
  userId: string,
  conversationId: string,
): Promise<HistoryMessage[]> {
  const { data, error } = await db
    .from("messages")
    .select("role, content, api_content, model")
    .eq("conversation_id", conversationId)
    .eq("user_id", userId)
    .eq("status", "complete")
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(HISTORY_LIMIT);
  if (error) throw new StoreError("db_error");
  return (data ?? []).reverse() as HistoryMessage[];
}

export interface SavedExchange {
  user_message: Record<string, unknown>;
  assistant_message: Record<string, unknown>;
}

const RETURN_COLUMNS = "id, conversation_id, role, content, status, created_at";

/**
 * AI 답변이 끝난 뒤 질문과 답변을 한 번의 insert로 함께 저장한다.
 * (한 문장이므로 둘 중 하나만 저장되는 일은 없다.)
 */
export async function saveExchange(
  db: SupabaseClient,
  input: {
    userId: string;
    conversationId: string;
    userText: string;
    reply: {
      text: string;
      apiContent: unknown[];
      model: string;
      stopReason: string | null;
      usage: {
        inputTokens: number;
        outputTokens: number;
        cacheReadTokens: number;
        cacheCreationTokens: number;
      };
    };
  },
): Promise<SavedExchange> {
  const { userId, conversationId, userText, reply } = input;
  const { data, error } = await db
    .from("messages")
    .insert([
      {
        conversation_id: conversationId,
        user_id: userId,
        role: "user",
        content: userText,
      },
      {
        conversation_id: conversationId,
        user_id: userId,
        role: "assistant",
        content: reply.text,
        api_content: reply.apiContent,
        model: reply.model.slice(0, 100),
        stop_reason: reply.stopReason?.slice(0, 50) ?? null,
        input_tokens: reply.usage.inputTokens,
        output_tokens: reply.usage.outputTokens,
        cache_read_tokens: reply.usage.cacheReadTokens,
        cache_creation_tokens: reply.usage.cacheCreationTokens,
      },
    ])
    .select(RETURN_COLUMNS);
  if (error || !data || data.length !== 2) {
    throw new StoreError("save_failed");
  }
  const user = data.find((r) => r.role === "user");
  const assistant = data.find((r) => r.role === "assistant");
  if (!user || !assistant) throw new StoreError("save_failed");
  return { user_message: user, assistant_message: assistant };
}

/** 사용량을 오늘 합계에 더한다. */
export async function recordUsage(
  db: SupabaseClient,
  userId: string,
  usage: {
    inputTokens: number;
    outputTokens: number;
    cacheReadTokens: number;
    cacheCreationTokens: number;
  },
): Promise<void> {
  const { error } = await db.rpc("record_usage", {
    p_user_id: userId,
    p_input_tokens: usage.inputTokens,
    p_output_tokens: usage.outputTokens,
    p_cache_read_tokens: usage.cacheReadTokens,
    p_cache_creation_tokens: usage.cacheCreationTokens,
  });
  if (error) throw new StoreError("usage_failed");
}
