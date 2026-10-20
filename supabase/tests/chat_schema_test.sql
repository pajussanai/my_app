-- =====================================================================
-- 축복 챗봇 1단계 스키마 검증 (pgTAP)
--
-- 실행: supabase test db
--   - 로컬 Supabase DB(supabase start)에서만 실행한다. 원격 DB에는 실행하지 않는다.
--   - 모든 작업은 하나의 트랜잭션 안에서 실행되고 마지막에 rollback 된다.
--   - 테스트용 사용자 2명(A, B)은 로컬 auth.users에만 잠시 만들어진다.
-- =====================================================================
begin;

create extension if not exists pgtap with schema extensions;

select plan(35);

-- 테스트 사용자 A, B
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'user-a@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'user-b@example.com');


-- ---------------------------------------------------------------------
-- 구조와 권한
-- ---------------------------------------------------------------------
select ok(
  (select bool_and(relrowsecurity) from pg_class
    where oid in ('public.conversations'::regclass, 'public.messages'::regclass,
                  'public.memories'::regclass, 'public.user_settings'::regclass,
                  'public.usage_daily'::regclass)),
  'T1 5개 테이블 모두 RLS가 켜져 있다'
);

select ok(
  not (select bool_or(has_table_privilege('anon', t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
                      or has_any_column_privilege('anon', t, 'SELECT,INSERT,UPDATE,REFERENCES'))
         from unnest(array['public.conversations', 'public.messages', 'public.memories',
                           'public.user_settings', 'public.usage_daily']) as t),
  'T2 anon은 어떤 테이블에도 권한이 없다'
);

select ok(
  not has_function_privilege('authenticated', 'public.record_usage(uuid,bigint,bigint,bigint,bigint)', 'execute'),
  'T3 authenticated는 record_usage()를 실행할 수 없다'
);

select ok(
  not has_function_privilege('anon', 'public.record_usage(uuid,bigint,bigint,bigint,bigint)', 'execute'),
  'T4 anon은 record_usage()를 실행할 수 없다'
);

select ok(
  not (has_table_privilege('authenticated', 'public.messages', 'INSERT')
       or has_table_privilege('authenticated', 'public.messages', 'UPDATE')
       or has_table_privilege('authenticated', 'public.messages', 'DELETE')
       or has_any_column_privilege('authenticated', 'public.messages', 'INSERT,UPDATE')),
  'T5 authenticated는 messages에 쓰기 권한이 없다'
);


-- ---------------------------------------------------------------------
-- 비로그인(anon)
-- ---------------------------------------------------------------------
set local role anon;

select throws_ok(
  $$ select * from public.conversations $$,
  '42501',
  null,
  'T6 anon은 대화 목록을 조회할 수 없다'
);

reset role;


-- ---------------------------------------------------------------------
-- 사용자 A
-- ---------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

select lives_ok(
  $$ insert into public.conversations (id, title)
     values ('aaaaaaaa-0000-0000-0000-000000000001', 'A의 대화') $$,
  'T7 A는 자기 대화를 만들 수 있다 (user_id는 기본값으로 A)'
);

select is(
  (select count(*) from public.conversations),
  1::bigint,
  'T8 A는 자기 대화 1개를 볼 수 있다'
);

select lives_ok(
  $$ update public.conversations set title = 'A의 대화 (수정)'
      where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  'T9 A는 제목을 바꿀 수 있다 (updated_at 트리거가 authenticated로 실행됨)'
);

select throws_ok(
  $$ update public.conversations set last_message_at = now()
      where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '42501',
  null,
  'T10 A는 last_message_at(서버 전용)을 바꿀 수 없다'
);

select throws_ok(
  $$ insert into public.messages (conversation_id, user_id, role, content)
     values ('aaaaaaaa-0000-0000-0000-000000000001',
             '11111111-1111-1111-1111-111111111111', 'assistant', '가짜 답변') $$,
  '42501',
  null,
  'T11 A는 메시지를 직접 넣을 수 없다 (자기 대화라도)'
);

select lives_ok(
  $$ insert into public.memories (id, content)
     values ('bbbbbbbb-0000-0000-0000-000000000001', 'A의 기억') $$,
  'T12 A는 기억을 직접 추가할 수 있다'
);

select throws_ok(
  $$ insert into public.memories (content, source) values ('자동인 척', 'auto') $$,
  '42501',
  null,
  'T13 A는 기억의 source(서버 전용)를 정할 수 없다'
);

select lives_ok(
  $$ insert into public.user_settings (memory_enabled) values (false) $$,
  'T14 A는 자기 설정 행을 만들 수 있다'
);

select throws_ok(
  $$ update public.user_settings set daily_message_limit = 100000
      where user_id = '11111111-1111-1111-1111-111111111111' $$,
  '42501',
  null,
  'T15 A는 하루 한도(서버 전용)를 바꿀 수 없다'
);

select throws_ok(
  $$ select public.record_usage('11111111-1111-1111-1111-111111111111', 1, 1, 0, 0) $$,
  '42501',
  null,
  'T16 A는 record_usage()를 호출할 수 없다'
);

select throws_ok(
  $$ insert into public.usage_daily (user_id, day, request_count)
     values ('11111111-1111-1111-1111-111111111111', current_date, 0) $$,
  '42501',
  null,
  'T17 A는 사용량을 직접 기록할 수 없다'
);


-- ---------------------------------------------------------------------
-- 사용자 B: A의 데이터에 접근할 수 없어야 한다
-- ---------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';

select is(
  (select count(*) from public.conversations),
  0::bigint,
  'T18 B는 A의 대화를 볼 수 없다'
);

select is(
  (select count(*) from public.memories),
  0::bigint,
  'T19 B는 A의 기억을 볼 수 없다'
);

select results_eq(
  $$ with u as (
       update public.conversations set title = '탈취'
        where id = 'aaaaaaaa-0000-0000-0000-000000000001'
       returning 1)
     select count(*) from u $$,
  $$ values (0::bigint) $$,
  'T20 B가 A의 대화 제목을 바꾸려 해도 바뀌는 행이 없다'
);

select results_eq(
  $$ with d as (
       delete from public.memories
        where id = 'bbbbbbbb-0000-0000-0000-000000000001'
       returning 1)
     select count(*) from d $$,
  $$ values (0::bigint) $$,
  'T21 B가 A의 기억을 지우려 해도 지워지는 행이 없다'
);

select throws_ok(
  $$ insert into public.conversations (user_id, title)
     values ('11111111-1111-1111-1111-111111111111', 'A인 척') $$,
  '42501',
  null,
  'T22 B는 A의 이름(user_id)으로 대화를 만들 수 없다'
);

select is(
  (select count(*) from public.user_settings),
  0::bigint,
  'T23 B는 A의 설정을 볼 수 없다'
);

reset role;


-- ---------------------------------------------------------------------
-- 서버(service_role): Edge Function이 하는 쓰기
-- ---------------------------------------------------------------------
set local role service_role;

select lives_ok(
  $$ insert into public.messages (conversation_id, user_id, role, content) values
       ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'user', '질문'),
       ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'assistant', '답변') $$,
  'T24 서버는 A의 대화에 질문과 답변을 저장할 수 있다'
);

select is(
  (select count(distinct created_at) from public.messages
    where conversation_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  2::bigint,
  'T25 한 문장으로 저장한 질문과 답변의 created_at이 서로 다르다 (순서 보장)'
);

select ok(
  (select last_message_at is not null from public.conversations
    where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'T26 메시지 저장 후 대화의 last_message_at이 갱신된다'
);

select throws_ok(
  $$ insert into public.messages (conversation_id, user_id, role, content)
     values ('aaaaaaaa-0000-0000-0000-000000000001',
             '22222222-2222-2222-2222-222222222222', 'user', '남의 대화에 끼워 넣기') $$,
  '23503',
  null,
  'T27 대화 주인과 다른 user_id로는 메시지를 저장할 수 없다 (서버라도)'
);

select lives_ok(
  $$ do $d$
     begin
       perform public.record_usage('11111111-1111-1111-1111-111111111111', 10, 20, 0, 0);
       perform public.record_usage('11111111-1111-1111-1111-111111111111', 5, 1, 0, 0);
     end
     $d$ $$,
  'T28 서버는 record_usage()로 사용량을 기록할 수 있다'
);

select results_eq(
  $$ select request_count, input_tokens, output_tokens,
            day = (now() at time zone 'Asia/Seoul')::date
       from public.usage_daily
      where user_id = '11111111-1111-1111-1111-111111111111' $$,
  $$ values (2, 15::bigint, 21::bigint, true) $$,
  'T29 같은 날 두 번 기록하면 한국 날짜 한 줄에 누적된다'
);

select lives_ok(
  $$ insert into public.memories (id, user_id, content, source, source_conversation_id)
     values ('bbbbbbbb-0000-0000-0000-000000000002',
             '11111111-1111-1111-1111-111111111111', '자동 기억', 'auto',
             'aaaaaaaa-0000-0000-0000-000000000001') $$,
  'T30 서버는 출처 대화를 가진 자동 기억을 저장할 수 있다'
);


-- ---------------------------------------------------------------------
-- 삭제 처리
-- ---------------------------------------------------------------------
select lives_ok(
  $$ delete from public.conversations where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  'T31 대화를 삭제할 수 있다'
);

select is(
  (select count(*) from public.messages
    where conversation_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  0::bigint,
  'T32 대화를 지우면 메시지도 함께 지워진다'
);

select ok(
  exists (select 1 from public.memories
           where id = 'bbbbbbbb-0000-0000-0000-000000000002'
             and source_conversation_id is null),
  'T33 대화를 지워도 기억은 남고 출처만 비워진다'
);

reset role;

select lives_ok(
  $$ delete from auth.users where id = '11111111-1111-1111-1111-111111111111' $$,
  'T34 계정을 삭제할 수 있다'
);

select is(
  (select (select count(*) from public.conversations where user_id = '11111111-1111-1111-1111-111111111111')
        + (select count(*) from public.memories      where user_id = '11111111-1111-1111-1111-111111111111')
        + (select count(*) from public.user_settings where user_id = '11111111-1111-1111-1111-111111111111')
        + (select count(*) from public.usage_daily   where user_id = '11111111-1111-1111-1111-111111111111')),
  0::bigint,
  'T35 계정을 지우면 그 사용자의 모든 데이터가 지워진다'
);

select * from finish();
rollback;
