-- =====================================================================
-- 축복 챗봇 1단계: 대화 기능 DB 스키마와 RLS 정책
--
-- 대상: Supabase 프로젝트 blessing-chatbot (sdwkhsdkkorxpouvroue), Postgres 17
-- 상태: 검토용 초안. 아직 서버에 적용하지 않았다.
--
-- 보안 원칙
--   1. 모든 테이블에 RLS를 켜고, 로그인 사용자(authenticated)는
--      자기 행(user_id = auth.uid())만 다룰 수 있다.
--   2. 비로그인 사용자(anon)는 어떤 테이블에도 접근할 수 없다.
--   3. RLS와 별도로 테이블 권한(GRANT)도 필요한 동작과 컬럼만 허용한다.
--      (RLS는 "어느 행", GRANT는 "어떤 동작·컬럼"을 막는다.)
--   4. messages와 usage_daily는 서버(Edge Function, service_role)만 쓴다.
--   5. 이 파일에는 API 키나 비밀값이 없다.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 공통 함수: updated_at 자동 갱신
-- ---------------------------------------------------------------------
create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.set_updated_at() from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- conversations: 사용자별 대화방
-- ---------------------------------------------------------------------
create table public.conversations (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        not null default auth.uid()
                              references auth.users (id) on delete cascade,
  title           text        check (title is null or char_length(title) between 1 and 200),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  -- 마지막 메시지 시각. messages 트리거가 갱신한다(목록 정렬용).
  last_message_at timestamptz,
  -- messages·memories가 (대화 id, 소유자)를 함께 참조하기 위한 키
  constraint conversations_id_user_id_key unique (id, user_id)
);

comment on table public.conversations is '사용자별 대화방. 본인만 조회·생성·제목 수정·삭제 가능.';

create index conversations_user_id_recent_idx
  on public.conversations (user_id, last_message_at desc nulls last, created_at desc);

create trigger conversations_set_updated_at
  before update on public.conversations
  for each row execute function public.set_updated_at();


-- ---------------------------------------------------------------------
-- messages: 대화별 사용자 메시지와 AI 응답
-- ---------------------------------------------------------------------
create table public.messages (
  id                    uuid        primary key default gen_random_uuid(),
  conversation_id       uuid        not null,
  -- 대화 소유자. 아래 복합 외래 키로 대화의 user_id와 반드시 같아야 한다.
  user_id               uuid        not null,
  role                  text        not null check (role in ('user', 'assistant')),
  -- 화면에 보여 줄 텍스트
  content               text        not null default '' check (char_length(content) <= 200000),
  -- AI API에 다시 보낼 원본 응답 블록(생각 블록 포함). 사용자 메시지는 null.
  api_content           jsonb,
  status                text        not null default 'complete'
                                    check (status in ('streaming', 'complete', 'error')),
  model                 text        check (model is null or char_length(model) <= 100),
  input_tokens          integer     check (input_tokens is null or input_tokens >= 0),
  output_tokens         integer     check (output_tokens is null or output_tokens >= 0),
  cache_read_tokens     integer     check (cache_read_tokens is null or cache_read_tokens >= 0),
  cache_creation_tokens integer     check (cache_creation_tokens is null or cache_creation_tokens >= 0),
  stop_reason           text        check (stop_reason is null or char_length(stop_reason) <= 50),
  error_code            text        check (error_code is null or char_length(error_code) <= 100),
  -- clock_timestamp(): 한 트랜잭션에서 질문과 답변을 함께 저장해도 시각이 달라
  -- 순서가 뒤바뀌지 않는다. (now()는 트랜잭션 안에서 항상 같은 값)
  created_at            timestamptz not null default clock_timestamp(),
  updated_at            timestamptz not null default now(),
  -- 다른 사람의 대화에 메시지를 넣을 수 없게 (대화 id, 소유자)를 함께 검증한다.
  -- 대화가 삭제되면 메시지도 함께 삭제된다.
  constraint messages_conversation_owner_fkey
    foreign key (conversation_id, user_id)
    references public.conversations (id, user_id)
    on delete cascade
);

comment on table public.messages is '대화 메시지. 본인 것만 조회 가능. 쓰기는 서버(service_role)만.';

create index messages_conversation_id_created_at_idx
  on public.messages (conversation_id, created_at, id);

create index messages_user_id_idx
  on public.messages (user_id);

create trigger messages_set_updated_at
  before update on public.messages
  for each row execute function public.set_updated_at();

-- 메시지가 추가되면 대화의 last_message_at을 갱신한다.
create function public.touch_conversation_last_message()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update public.conversations
     set last_message_at = greatest(coalesce(last_message_at, new.created_at), new.created_at)
   where id = new.conversation_id;
  return null;
end;
$$;

revoke all on function public.touch_conversation_last_message() from public, anon, authenticated;

create trigger messages_touch_conversation
  after insert on public.messages
  for each row execute function public.touch_conversation_last_message();


-- ---------------------------------------------------------------------
-- memories: 사용자별 장기 기억
-- ---------------------------------------------------------------------
create table public.memories (
  id                     uuid        primary key default gen_random_uuid(),
  user_id                uuid        not null default auth.uid()
                                     references auth.users (id) on delete cascade,
  content                text        not null check (char_length(btrim(content)) between 1 and 500),
  -- 'user': 사용자가 직접 추가, 'auto': 서버가 대화에서 추출
  source                 text        not null default 'user' check (source in ('user', 'auto')),
  -- 자동 추출된 기억의 출처 대화. 대화를 지우면 출처만 비운다(기억은 남김).
  source_conversation_id uuid,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  -- 출처 대화도 같은 사용자의 것이어야 한다.
  constraint memories_source_conversation_fkey
    foreign key (source_conversation_id, user_id)
    references public.conversations (id, user_id)
    on delete set null (source_conversation_id)
);

comment on table public.memories is '사용자별 장기 기억. 본인만 조회·추가·수정·삭제 가능. source·출처 대화는 서버만 설정.';

create index memories_user_id_created_at_idx
  on public.memories (user_id, created_at desc);

create index memories_source_conversation_id_idx
  on public.memories (source_conversation_id)
  where source_conversation_id is not null;

create trigger memories_set_updated_at
  before update on public.memories
  for each row execute function public.set_updated_at();


-- ---------------------------------------------------------------------
-- user_settings: 사용자별 앱 설정 (행이 없으면 기본값으로 본다)
-- ---------------------------------------------------------------------
create table public.user_settings (
  user_id             uuid        primary key default auth.uid()
                                  references auth.users (id) on delete cascade,
  memory_enabled      boolean     not null default true,
  -- 하루 메시지 한도. null = 한도 없음(초기값). 서버(service_role)만 변경한다.
  daily_message_limit integer     check (daily_message_limit is null or daily_message_limit >= 0),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table public.user_settings is '사용자 설정. 본인은 memory_enabled만 바꿀 수 있고, 한도는 서버만 바꾼다.';

-- 행이 없을 때의 처리 (앱·서버 공통 규칙)
--   읽기: 행이 없으면 memory_enabled = true, daily_message_limit = null(한도 없음)으로 본다.
--   앱에서 쓰기: update(memory_enabled)를 먼저 시도하고, 바뀐 행이 없으면 insert한다.
--     PostgREST의 upsert(merge-duplicates)는 user_id 컬럼까지 UPDATE하려 해서
--     update 권한이 memory_enabled에만 있는 이 테이블에서는 거부된다(의도된 제한).

create trigger user_settings_set_updated_at
  before update on public.user_settings
  for each row execute function public.set_updated_at();


-- ---------------------------------------------------------------------
-- usage_daily: 날짜별 사용량 (비용·요청 제한 준비)
-- ---------------------------------------------------------------------
create table public.usage_daily (
  user_id               uuid        not null references auth.users (id) on delete cascade,
  -- 한국 시간(Asia/Seoul) 기준 날짜. record_usage()가 정한다.
  day                   date        not null,
  request_count         integer     not null default 0 check (request_count >= 0),
  input_tokens          bigint      not null default 0 check (input_tokens >= 0),
  output_tokens         bigint      not null default 0 check (output_tokens >= 0),
  cache_read_tokens     bigint      not null default 0 check (cache_read_tokens >= 0),
  cache_creation_tokens bigint      not null default 0 check (cache_creation_tokens >= 0),
  updated_at            timestamptz not null default now(),
  primary key (user_id, day)
);

comment on table public.usage_daily is '사용자별 일일 사용량. 본인은 조회만 가능. 기록은 서버가 record_usage()로만 한다.';

-- 서버 전용: AI 요청 1건의 사용량을 오늘 합계에 더한다.
-- 동시에 여러 요청이 와도 upsert 한 번으로 안전하게 누적된다.
create function public.record_usage(
  p_user_id               uuid,
  p_input_tokens          bigint default 0,
  p_output_tokens         bigint default 0,
  p_cache_read_tokens     bigint default 0,
  p_cache_creation_tokens bigint default 0
)
returns void
language sql
security invoker
set search_path = ''
as $$
  insert into public.usage_daily as u
    (user_id, day, request_count,
     input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens)
  values
    (p_user_id, (now() at time zone 'Asia/Seoul')::date, 1,
     p_input_tokens, p_output_tokens, p_cache_read_tokens, p_cache_creation_tokens)
  on conflict (user_id, day) do update
    set request_count         = u.request_count + 1,
        input_tokens          = u.input_tokens + excluded.input_tokens,
        output_tokens         = u.output_tokens + excluded.output_tokens,
        cache_read_tokens     = u.cache_read_tokens + excluded.cache_read_tokens,
        cache_creation_tokens = u.cache_creation_tokens + excluded.cache_creation_tokens,
        updated_at            = now();
$$;

-- 앱(anon·authenticated)은 이 함수를 호출할 수 없다. 서버만 호출한다.
revoke all on function public.record_usage(uuid, bigint, bigint, bigint, bigint)
  from public, anon, authenticated;
grant execute on function public.record_usage(uuid, bigint, bigint, bigint, bigint)
  to service_role;


-- =====================================================================
-- 테이블 권한(GRANT): 동작·컬럼 단위로 필요한 것만 허용
-- =====================================================================
revoke all on table
  public.conversations, public.messages, public.memories,
  public.user_settings, public.usage_daily
  from anon, authenticated;

-- 서버(Edge Function)용 역할. RLS를 우회하므로 Flutter 앱에는 절대 넣지 않는다.
grant all on table
  public.conversations, public.messages, public.memories,
  public.user_settings, public.usage_daily
  to service_role;

-- conversations: 조회·삭제, 추가(id·user_id·title), 제목만 수정
grant select, delete on table public.conversations to authenticated;
grant insert (id, user_id, title) on table public.conversations to authenticated;
grant update (title) on table public.conversations to authenticated;

-- messages: 조회만
grant select on table public.messages to authenticated;

-- memories: 조회·삭제, 추가(id·user_id·content), 내용만 수정
grant select, delete on table public.memories to authenticated;
grant insert (id, user_id, content) on table public.memories to authenticated;
grant update (content) on table public.memories to authenticated;

-- user_settings: 조회, 추가·수정은 memory_enabled만 (daily_message_limit은 불가)
grant select on table public.user_settings to authenticated;
grant insert (user_id, memory_enabled) on table public.user_settings to authenticated;
grant update (memory_enabled) on table public.user_settings to authenticated;

-- usage_daily: 조회만
grant select on table public.usage_daily to authenticated;


-- =====================================================================
-- RLS: 본인 행만
-- =====================================================================
alter table public.conversations enable row level security;
alter table public.messages      enable row level security;
alter table public.memories      enable row level security;
alter table public.user_settings enable row level security;
alter table public.usage_daily   enable row level security;

-- conversations
create policy conversations_select_own on public.conversations
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy conversations_insert_own on public.conversations
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy conversations_update_own on public.conversations
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy conversations_delete_own on public.conversations
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- messages: 조회만 (쓰기 정책 없음 → 앱에서는 추가·수정·삭제 불가)
create policy messages_select_own on public.messages
  for select to authenticated
  using ((select auth.uid()) = user_id);

-- memories
create policy memories_select_own on public.memories
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy memories_insert_own on public.memories
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy memories_update_own on public.memories
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy memories_delete_own on public.memories
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- user_settings (삭제 정책 없음)
create policy user_settings_select_own on public.user_settings
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy user_settings_insert_own on public.user_settings
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy user_settings_update_own on public.user_settings
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- usage_daily: 조회만 (쓰기 정책 없음)
create policy usage_daily_select_own on public.usage_daily
  for select to authenticated
  using ((select auth.uid()) = user_id);
