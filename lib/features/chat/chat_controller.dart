import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors.dart';
import '../../models/chat_message.dart';
import '../../models/chat_usage.dart';
import '../../models/conversation.dart';
import '../../services/chat_repository.dart';

/// 채팅 화면의 상태: 대화 목록, 선택한 대화, 메시지, 전송 중 여부.
///
/// 화면 위젯과 분리해 두어 위젯 없이도 테스트할 수 있다.
class ChatController extends ChangeNotifier {
  ChatController(this._repository);

  final ChatRepository _repository;

  List<Conversation> _conversations = [];
  bool _loadingConversations = true;
  String? _conversationsError;

  /// null이면 아직 만들지 않은 "새 대화" 상태
  String? _selectedId;
  List<ChatMessage> _messages = [];
  bool _loadingMessages = false;
  String? _messagesError;

  bool _sending = false;
  String? _notice;
  bool _disposed = false;

  List<Conversation> get conversations => _conversations;
  bool get loadingConversations => _loadingConversations;
  String? get conversationsError => _conversationsError;
  String? get selectedId => _selectedId;
  List<ChatMessage> get messages => _messages;
  bool get loadingMessages => _loadingMessages;
  String? get messagesError => _messagesError;
  bool get sending => _sending;
  bool get isDemo => _repository.isDemo;
  bool get savesConversations => _repository.savesConversations;

  /// 화면 아래에 잠깐 보여 줄 안내(예: 삭제 실패). 보여 준 뒤 [clearNotice]로 지운다.
  String? get notice => _notice;

  Conversation? get selectedConversation {
    for (final c in _conversations) {
      if (c.id == _selectedId) return c;
    }
    return null;
  }

  String get title => selectedConversation?.displayTitle ?? '새 대화';

  /// 마지막 답변이 실패했으면 다시 시도할 수 있다.
  bool get canRetry =>
      !_sending &&
      _messages.isNotEmpty &&
      _messages.last.status == MessageStatus.error &&
      _lastFailedText != null;

  String? _lastFailedText;

  ChatUsage? _usage;
  String? _usageError;
  String? _limitCode;
  DateTime? _limitAt;

  /// 오늘의 AI 사용량(앱 집계). AI 서버를 쓰지 않으면 null.
  ChatUsage? get usage => _usage;
  String? get usageError => _usageError;

  /// 마지막으로 받은 사용 제한 오류 코드(ai_quota_exceeded, ai_rate_limited,
  /// daily_limit_reached)와 시각. 이번 접속에서 받은 것만 기억한다.
  String? get limitCode => _limitCode;
  DateTime? get limitAt => _limitAt;

  static const _limitCodes = {
    'ai_quota_exceeded',
    'ai_rate_limited',
    'daily_limit_reached',
  };

  /// 사용량을 다시 불러온다. AI를 호출하지 않는다. 실패해도 채팅에는 영향이 없다.
  Future<void> loadUsage() async {
    try {
      _usage = await _repository.fetchUsage();
      _usageError = null;
    } catch (e) {
      logError('사용량 불러오기 실패', e);
      _usageError = describeError(e);
    }
    _notify();
  }

  Future<void> loadConversations() async {
    _loadingConversations = true;
    _conversationsError = null;
    _notify();
    try {
      unawaited(loadUsage());
      _conversations = await _repository.fetchConversations();
    } catch (e) {
      logError('대화 목록 불러오기 실패', e);
      _conversationsError = describeError(e);
    } finally {
      _loadingConversations = false;
      _notify();
    }
  }

  void startNewConversation() {
    if (_sending) return;
    _selectedId = null;
    _messages = [];
    _messagesError = null;
    _lastFailedText = null;
    _notify();
  }

  Future<void> selectConversation(String id) async {
    if (_sending || id == _selectedId) return;
    _selectedId = id;
    _messages = [];
    _messagesError = null;
    _lastFailedText = null;
    _loadingMessages = true;
    _notify();
    try {
      final loaded = await _repository.fetchMessages(id);
      // 그사이 다른 대화를 골랐으면 버린다.
      if (_selectedId == id) _messages = loaded;
    } catch (e) {
      logError('메시지 불러오기 실패', e);
      if (_selectedId == id) _messagesError = describeError(e);
    } finally {
      if (_selectedId == id) _loadingMessages = false;
      _notify();
    }
  }

  /// 메시지 불러오기에 실패했을 때 다시 불러온다.
  Future<void> reloadMessages() async {
    final id = _selectedId;
    if (id == null || _sending) return;
    _selectedId = null;
    await selectConversation(id);
  }

  /// 메시지를 보낸다. 질문이 화면에 올라가면 true(입력창을 비워도 됨),
  /// 보낼 수 없으면 false(입력 내용을 남겨 둔다)를 돌려준다.
  /// 답변은 그 뒤에도 계속 받아서 화면에 반영한다.
  Future<bool> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return false;

    _sending = true;
    _notify();

    var conversationId = _selectedId;
    if (conversationId == null) {
      try {
        final created = await _repository.createConversation(
          title: Conversation.titleFrom(trimmed),
        );
        _conversations = [created, ..._conversations];
        _selectedId = conversationId = created.id;
        _messages = [];
      } catch (e) {
        logError('대화 만들기 실패', e);
        _sending = false;
        _notice = '대화를 시작하지 못했습니다. ${describeError(e)}';
        _notify();
        return false;
      }
    }

    _startReply(conversationId, trimmed);
    return true;
  }

  /// 실패한 마지막 질문을 다시 보낸다.
  Future<void> retry() async {
    final text = _lastFailedText;
    if (!canRetry || text == null) return;
    // 실패한 질문과 답변을 화면에서 지우고 다시 보낸다.
    _messages = _messages.sublist(0, _messages.length - 2);
    _lastFailedText = null;
    await send(text);
  }

  Future<void> deleteConversation(String id) async {
    if (_sending) return;
    try {
      await _repository.deleteConversation(id);
      _conversations = _conversations.where((c) => c.id != id).toList();
      if (_selectedId == id) {
        _selectedId = null;
        _messages = [];
        _messagesError = null;
        _lastFailedText = null;
      }
    } catch (e) {
      logError('대화 삭제 실패', e);
      _notice = '대화를 삭제하지 못했습니다. ${describeError(e)}';
    }
    _notify();
  }

  void clearNotice() {
    _notice = null;
  }

  void _startReply(String conversationId, String text) {
    final now = DateTime.now();
    final userDraft = ChatMessage(
      id: 'local-user-${now.microsecondsSinceEpoch}',
      conversationId: conversationId,
      role: ChatRole.user,
      content: text,
      createdAt: now,
    );
    final assistantDraft = ChatMessage(
      id: 'local-assistant-${now.microsecondsSinceEpoch}',
      conversationId: conversationId,
      role: ChatRole.assistant,
      content: '',
      createdAt: now,
      status: MessageStatus.streaming,
    );
    _messages = [..._messages, userDraft, assistantDraft];
    _notify();

    unawaited(_receive(conversationId, text, userDraft.id, assistantDraft.id));
  }

  Future<void> _receive(
    String conversationId,
    String text,
    String userDraftId,
    String assistantDraftId,
  ) async {
    void updateAssistant(ChatMessage Function(ChatMessage m) change) {
      if (_selectedId != conversationId) return;
      _messages = [
        for (final m in _messages) m.id == assistantDraftId ? change(m) : m,
      ];
    }

    void fail(Object error, {bool userMessageSaved = false}) {
      logError('답변 받기 실패', error);
      if (error is ChatServiceException && _limitCodes.contains(error.code)) {
        _limitCode = error.code;
        _limitAt = DateTime.now();
      }
      _lastFailedText = text;
      updateAssistant(
        (m) => m.copyWith(
          status: MessageStatus.error,
          errorMessage: '답변을 받지 못했습니다. ${describeError(error)}',
        ),
      );
      // 질문도 저장되지 않았으면 저장된 것처럼 보이지 않게 표시한다.
      if (!userMessageSaved && _selectedId == conversationId) {
        _messages = [
          for (final m in _messages)
            m.id == userDraftId ? m.copyWith(status: MessageStatus.error) : m,
        ];
      }
    }

    try {
      await for (final event in _repository.sendMessage(
        conversationId: conversationId,
        text: text,
      )) {
        switch (event) {
          case ChatReplyDelta(:final text):
            updateAssistant((m) => m.copyWith(content: m.content + text));
          case ChatReplyRestart():
            updateAssistant((m) => m.copyWith(content: ''));
          case ChatReplyDone(:final userMessage, :final assistantMessage):
            if (_selectedId == conversationId) {
              _messages = [
                for (final m in _messages)
                  if (m.id == userDraftId)
                    userMessage
                  else if (m.id == assistantDraftId)
                    assistantMessage
                  else
                    m,
              ];
            }
            _touchConversation(conversationId, assistantMessage.createdAt);
            // 답변을 받았으면 Google 쪽 제한은 풀린 것이다.
            _limitCode = null;
            _limitAt = null;
          case ChatReplyFailed(:final error, :final userMessageSaved):
            fail(error, userMessageSaved: userMessageSaved);
        }
        _notify();
      }
    } catch (e) {
      fail(e);
    } finally {
      _sending = false;
      _notify();
      // 답변이 끝난 뒤 사용량을 새로 고친다(DB 조회만, AI 호출 없음).
      unawaited(loadUsage());
    }
  }

  /// 답변을 받은 대화를 목록 맨 위로 올린다.
  void _touchConversation(String id, DateTime at) {
    Conversation? touched;
    final rest = <Conversation>[];
    for (final c in _conversations) {
      if (c.id == id) {
        touched = c.copyWith(lastMessageAt: at);
      } else {
        rest.add(c);
      }
    }
    if (touched != null) _conversations = [touched, ...rest];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
