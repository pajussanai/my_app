// Anthropic Claude로 답변을 만든다(이전 구현. AI_PROVIDER=claude일 때만 쓴다).
import Anthropic from "@anthropic-ai/sdk";
import {
  AiError,
  buildTurns,
  type GeneratedReply,
  type GenerateOptions,
  replayableContent,
  SYSTEM_PROMPT,
} from "./ai.ts";

export const CLAUDE_DEFAULT_MODEL = "claude-opus-5-5";

type ContentBlocks = Array<Record<string, unknown>>;

/** 대체 모델로 넘어간 경우, 마지막 대체 지점 뒤의 글만 답변으로 쓴다. */
function finalText(content: ContentBlocks): string {
  let start = 0;
  content.forEach((block, i) => {
    if (block.type === "fallback") start = i + 1;
  });
  return content
    .slice(start)
    .filter((b) => b.type === "text")
    .map((b) => String(b.text ?? ""))
    .join("");
}

function toAiError(error: unknown, signal: AbortSignal): AiError {
  if (signal.aborted || error instanceof Anthropic.APIUserAbortError) {
    return new AiError("cancelled");
  }
  if (error instanceof Anthropic.APIConnectionTimeoutError) {
    return new AiError("timeout");
  }
  if (error instanceof Anthropic.RateLimitError) {
    return new AiError("ai_rate_limited");
  }
  if (
    error instanceof Anthropic.AuthenticationError ||
    error instanceof Anthropic.PermissionDeniedError
  ) {
    return new AiError("ai_not_configured");
  }
  if (error instanceof Anthropic.InternalServerError) {
    // 529(과부하)도 여기에 포함된다.
    return new AiError("ai_overloaded");
  }
  if (error instanceof Anthropic.APIConnectionError) {
    return new AiError("ai_unreachable");
  }
  if (error instanceof Anthropic.APIError) {
    return new AiError("ai_request_failed");
  }
  return new AiError("internal_error");
}

/**
 * Claude API를 스트리밍으로 호출한다. 글 조각이 올 때마다 onText를,
 * 대체 모델로 넘어가 앞의 글을 버려야 할 때 onRestart를 부른다.
 */
export async function generateWithClaude(
  options: GenerateOptions,
): Promise<GeneratedReply> {
  const { apiKey, history, userText, signal, onText, onRestart } = options;
  const client = new Anthropic({ apiKey, timeout: 90_000, maxRetries: 1 });
  const model = Deno.env.get("CLAUDE_MODEL") || CLAUDE_DEFAULT_MODEL;
  const useFallback = Deno.env.get("CHAT_REFUSAL_FALLBACK") !== "off";

  const messages = buildTurns<Record<string, unknown>>(
    history,
    userText,
    (m) => replayableContent(m, "claude") ?? [{ type: "text", text: m.content }],
  ).map((t) => ({ role: t.role, content: t.blocks }));

  const params = {
    model,
    max_tokens: 8000,
    system: SYSTEM_PROMPT,
    // 고정된 시스템 프롬프트와 이전 대화를 캐시해 다시 보낼 때 비용을 줄인다.
    cache_control: { type: "ephemeral" },
    // 일반 대화는 낮은 effort로도 충분하다(필요하면 측정 후 조정).
    output_config: { effort: "low" },
    messages,
    // 안전 분류기가 거절하면 서버가 다른 모델로 이어서 답한다.
    ...(useFallback
      ? { betas: ["server-side-fallback-2026-07-01"], fallbacks: "default" }
      : {}),
  };

  try {
    // deno-lint-ignore no-explicit-any
    const stream = client.beta.messages.stream(params as any, { signal });
    for await (const event of stream) {
      if (
        event.type === "content_block_start" &&
        // deno-lint-ignore no-explicit-any
        (event.content_block as any).type === "fallback"
      ) {
        onRestart();
      } else if (
        event.type === "content_block_delta" &&
        event.delta.type === "text_delta"
      ) {
        onText(event.delta.text);
      }
    }
    const message = await stream.finalMessage();
    const content = message.content as unknown as ContentBlocks;
    const usage = message.usage as unknown as Record<string, number | null>;
    return {
      text: finalText(content),
      apiContent: content,
      model: message.model,
      stopReason: message.stop_reason ?? null,
      refused: message.stop_reason === "refusal",
      usage: {
        inputTokens: usage.input_tokens ?? 0,
        outputTokens: usage.output_tokens ?? 0,
        cacheReadTokens: usage.cache_read_input_tokens ?? 0,
        cacheCreationTokens: usage.cache_creation_input_tokens ?? 0,
      },
    };
  } catch (error) {
    throw toAiError(error, signal);
  }
}
