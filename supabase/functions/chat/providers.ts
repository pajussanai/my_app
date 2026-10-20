// 어떤 AI 제공자로 답변을 만들지 고른다.
//
// 서버 비밀값
//   AI_PROVIDER        gemini(기본) | claude   ← claude로 바꾸면 이전 구현으로 되돌아간다
//   GEMINI_API_KEY     AI_PROVIDER=gemini일 때 필요
//   ANTHROPIC_API_KEY  AI_PROVIDER=claude일 때 필요
import type { AiProvider, GeneratedReply, GenerateOptions } from "./ai.ts";
import {
  CLAUDE_DEFAULT_MODEL,
  generateWithClaude,
} from "./claude.ts";
import {
  DEFAULT_MODEL as GEMINI_DEFAULT_MODEL,
  generateWithGemini,
} from "./gemini.ts";

/** 현재 설정된 제공자와 키. 키가 없거나 제공자 이름이 틀리면 null. */
export function aiConfig(): { provider: AiProvider; apiKey: string } | null {
  const provider = Deno.env.get("AI_PROVIDER") || "gemini";
  if (provider !== "gemini" && provider !== "claude") return null;
  const apiKey = Deno.env.get(
    provider === "gemini" ? "GEMINI_API_KEY" : "ANTHROPIC_API_KEY",
  );
  return apiKey ? { provider, apiKey } : null;
}

/** 현재 서버 설정의 제공자와 모델 이름(키 없이도 알려 준다). */
export function currentModel(): { provider: string; model: string } {
  const provider = Deno.env.get("AI_PROVIDER") || "gemini";
  return {
    provider,
    model: provider === "claude"
      ? Deno.env.get("CLAUDE_MODEL") || CLAUDE_DEFAULT_MODEL
      : Deno.env.get("GEMINI_MODEL") || GEMINI_DEFAULT_MODEL,
  };
}

export function generateReply(
  provider: AiProvider,
  options: GenerateOptions,
): Promise<GeneratedReply> {
  return provider === "gemini"
    ? generateWithGemini(options)
    : generateWithClaude(options);
}
