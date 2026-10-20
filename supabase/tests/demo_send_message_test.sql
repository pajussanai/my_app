-- =====================================================================
-- demo_send_message() 검증 (pgTAP)
--
-- 모든 작업은 하나의 트랜잭션 안에서 실행되고 마지막에 rollback 된다.
-- 데이터는 고정 id로만 만들고 지운다.
-- =====================================================================
begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'user-a@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'user-b@example.com');

insert into public.conversations (id, user_id, title) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'A의 대화');


-- 권한과 설정
select ok(
  not has_function_privilege('anon', 'public.demo_send_message(uuid,text)', 'execute'),
  'D1 anon은 demo_send_message()를 실행할 수 없다'
);

select ok(
  has_function_privilege('authenticated', 'public.demo_send_message(uuid,text)', 'execute'),
  'D2 로그인 사용자는 demo_send_message()를 실행할 수 있다'
);

select ok(
  (select prosecdef and proconfig = array['search_path=""']
     from pg_proc where oid = 'public.demo_send_message(uuid,text)'::regprocedure),
  'D3 관리자 권한으로 실행되고 search_path가 고정되어 있다'
);


-- 사용자 A
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

select results_eq(
  $$ select count(*) from public.demo_send_message(
       'aaaaaaaa-0000-0000-0000-000000000001', '  안녕하세요  ') $$,
  $$ values (2::bigint) $$,
  'D4 A는 자기 대화에 질문을 보내면 질문과 답변 2개가 저장된다'
);

select results_eq(
  $$ select role, content from public.messages
      where conversation_id = 'aaaaaaaa-0000-0000-0000-000000000001'
      order by created_at, id $$,
  $$ values ('user', '  안녕하세요  '),
            ('assistant', '아직 AI 서버가 연결되지 않아 데모 답변을 보여 드려요.' || chr(10) || '보내신 메시지: "안녕하세요"') $$,
  'D5 질문이 먼저, 답변은 DB가 정한 데모 문구로 저장된다'
);

select ok(
  (select bool_and(user_id = '11111111-1111-1111-1111-111111111111')
     from public.messages
    where conversation_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'D6 저장된 메시지의 user_id는 로그인 사용자(A)다'
);

select throws_ok(
  $$ select public.demo_send_message('aaaaaaaa-0000-0000-0000-000000000001', '   ') $$,
  '22023',
  null,
  'D7 공백뿐인 질문은 거부한다'
);

select throws_ok(
  $$ select public.demo_send_message('aaaaaaaa-0000-0000-0000-000000000001', repeat('가', 4001)) $$,
  '22023',
  null,
  'D8 4000자를 넘는 질문은 거부한다'
);

select throws_ok(
  $$ select public.demo_send_message('aaaaaaaa-0000-0000-0000-00000000ffff', '없는 대화') $$,
  'P0002',
  null,
  'D9 없는 대화에는 보낼 수 없다'
);


-- 사용자 B: A의 대화에 보낼 수 없다
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';

select throws_ok(
  $$ select public.demo_send_message('aaaaaaaa-0000-0000-0000-000000000001', '끼워 넣기') $$,
  'P0002',
  null,
  'D10 B는 A의 대화에 메시지를 보낼 수 없다'
);

reset role;

select is(
  (select count(*) from public.messages
    where conversation_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  2::bigint,
  'D11 실패한 시도는 아무것도 저장하지 않았다'
);


-- 비로그인
set local role anon;

select throws_ok(
  $$ select public.demo_send_message('aaaaaaaa-0000-0000-0000-000000000001', '익명') $$,
  '42501',
  null,
  'D12 anon은 호출할 수 없다'
);

reset role;

select * from finish();
rollback;
