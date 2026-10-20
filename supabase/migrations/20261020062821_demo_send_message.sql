-- =====================================================================
-- 데모 단계 전용: 질문과 데모 답변 저장
--
-- messages는 서버만 쓴다(앱이 AI 답변을 위조하지 못하게). AI 서버(Edge Function)가
-- 준비되기 전까지 앱이 대화를 저장할 수 있도록, 이 함수가 서버 쪽에서
-- "로그인 사용자의 질문"과 "DB가 정한 데모 답변"을 함께 저장한다.
--
-- - 사용자는 auth.uid()로만 정한다(앱이 넘기는 사용자 id를 믿지 않는다).
-- - 답변 내용은 앱이 정할 수 없다.
-- - 자기 대화에만, 비어 있지 않은 4000자 이하 질문만 저장한다.
-- - Edge Function이 준비되면 이 함수를 삭제하는 마이그레이션을 따로 만든다.
--   본 프로젝트에는 적용하지 않는다.
-- =====================================================================

create function public.demo_send_message(
  p_conversation_id uuid,
  p_content         text
)
returns setof public.messages
language plpgsql
-- messages 쓰기 권한이 없는 로그인 사용자를 대신해 저장한다. 소유자 확인은 아래에서 직접 한다.
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.' using errcode = '42501';
  end if;

  if p_content is null
     or char_length(btrim(p_content)) = 0
     or char_length(p_content) > 4000 then
    raise exception '메시지가 비어 있거나 너무 깁니다.' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.conversations
     where id = p_conversation_id and user_id = v_user
  ) then
    raise exception '대화를 찾을 수 없습니다.' using errcode = 'P0002';
  end if;

  -- 한 문장으로 저장해 질문과 답변이 함께 저장되거나 함께 실패한다.
  -- created_at(clock_timestamp)이 행마다 달라 질문이 항상 먼저 정렬된다.
  return query
    insert into public.messages (conversation_id, user_id, role, content)
    values
      (p_conversation_id, v_user, 'user', p_content),
      (p_conversation_id, v_user, 'assistant',
       '아직 AI 서버가 연결되지 않아 데모 답변을 보여 드려요.' || chr(10)
         || '보내신 메시지: "' || btrim(p_content) || '"')
    returning *;
end;
$$;

revoke all on function public.demo_send_message(uuid, text) from public, anon, authenticated;
grant execute on function public.demo_send_message(uuid, text) to authenticated, service_role;
