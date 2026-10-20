import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';

/// 메시지 입력창과 보내기 버튼.
///
/// 데스크톱 운영체제(웹 포함)에서는 Enter로 보내고 Shift+Enter·Ctrl+Enter로 줄바꿈한다.
/// 휴대폰(Android·iOS, 앱과 모바일 브라우저 모두)에서는 키보드 Enter가 줄바꿈이고
/// 보내기 버튼으로 보낸다. 휴대폰 키보드에는 Shift+Enter가 없기 때문이다.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.sending,
    required this.onSend,
  });

  /// 답변을 받는 중이면 보내기를 막는다(입력은 계속 할 수 있다).
  final bool sending;

  /// 보낸 질문이 화면에 올라가면 true를 돌려준다. 그때만 입력창을 비운다.
  final Future<bool> Function(String text) onSend;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();

  /// 직전 입력 상태. 입력기가 Enter를 줄바꿈으로 넣었는지 비교하는 데 쓴다.
  TextEditingValue _previous = TextEditingValue.empty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onValueChanged);
  }

  void _onValueChanged() {
    final value = _controller.value;
    final previous = _previous;
    _previous = value;
    if (_enterSends && _isPlainEnterNewline(previous, value)) {
      _sendInsteadOfNewline(value);
      return;
    }
    setState(() {});
  }

  /// 한글처럼 조합해서 입력하면, 마지막 글자를 조합하는 중에 누른 Enter는
  /// 입력기가 먼저 받아 글자를 확정한 뒤 줄바꿈으로 넣는다(키 처리로는 막을 수 없다).
  /// 조합이 끝난 뒤 커서 자리에 줄바꿈 한 글자만 들어온 경우를 Enter로 본다.
  /// Shift 등 조합키를 누른 경우, 붙여넣기처럼 여러 글자가 들어온 경우는 해당하지 않는다.
  bool _isPlainEnterNewline(TextEditingValue before, TextEditingValue after) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return false;
    }
    if (after.composing.isValid || !after.selection.isCollapsed) return false;
    final caret = after.selection.baseOffset;
    if (caret <= 0 || caret > after.text.length) return false;
    if (after.text[caret - 1] != '\n') return false;
    if (after.text.length != before.text.length + 1) return false;
    return after.text.replaceRange(caret - 1, caret, '') == before.text;
  }

  /// 들어온 줄바꿈을 지우고 보낸다(보낼 수 없는 상태면 지우기만 한다).
  void _sendInsteadOfNewline(TextEditingValue value) {
    final caret = value.selection.baseOffset;
    final restored = TextEditingValue(
      text: value.text.replaceRange(caret - 1, caret, ''),
      selection: TextSelection.collapsed(offset: caret - 1),
    );
    _previous = restored;
    _controller.value = restored;
    _submit();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSend => !widget.sending && _controller.text.trim().isNotEmpty;

  /// 웹에서는 브라우저가 실행 중인 운영체제가 들어온다.
  static bool get _enterSends => switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => true,
    _ => false,
  };

  Future<void> _submit() async {
    if (!_canSend) return;
    final accepted = await widget.onSend(_controller.text);
    if (accepted && mounted) _controller.clear();
  }

  static const _maxLength = 4000;

  /// 커서 자리에 줄바꿈을 넣는다(선택한 글자가 있으면 바꾼다). 최대 길이를 넘기지 않는다.
  void _insertNewline() {
    final value = _controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final text = value.text.replaceRange(selection.start, selection.end, '\n');
    if (text.length > _maxLength) return;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: selection.start + 1),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!_enterSends) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    // Ctrl+Enter는 줄바꿈. 브라우저 입력창에는 Ctrl+Enter 기본 동작이 없어서 직접 넣는다.
    // 조합 중이면 입력기가 글자를 확정하도록 두고, 확정된 뒤의 Ctrl+Enter에서 넣는다.
    if (keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed) {
      if (_controller.value.composing.isValid) return KeyEventResult.ignored;
      if (event is! KeyUpEvent) _insertNewline();
      return KeyEventResult.handled;
    }
    // Shift+Enter는 입력창 기본 동작(줄바꿈), 다른 조합키도 기본 동작에 맡긴다.
    if (keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    // 한글 등을 조합하는 중이면 입력기가 글자를 확정하도록 둔다.
    // (조합 중에 보내면 마지막 글자가 사라지거나 입력창에 남는다.)
    // 이때 들어오는 줄바꿈은 _isPlainEnterNewline이 받아서 보낸다.
    if (_controller.value.composing.isValid) return KeyEventResult.ignored;

    if (event is KeyDownEvent) _submit();
    // 비어 있거나 답변을 받는 중이어도 Enter로 줄바꿈이 들어가지 않게 한다.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: softShadow,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _onKeyEvent,
                child: _buildField(),
              ),
            ),
            const SizedBox(width: 10),
            _SendButton(
              sending: widget.sending,
              onPressed: _canSend ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField() {
    return TextField(
      key: const Key('chatInput'),
      controller: _controller,
      minLines: 1,
      maxLines: 5,
      maxLength: _maxLength,
      textInputAction: TextInputAction.newline,
      style: const TextStyle(fontSize: 15, color: AppColors.textMain),
      decoration: appFieldDecoration(
        hintText: _enterSends
            ? '뱃속 아기에게 말을 걸어 보세요 (Shift+Enter·Ctrl+Enter 줄바꿈)'
            : '뱃속 아기에게 말을 걸어 보세요',
        hintStyle: const TextStyle(color: AppColors.textSub),
        fillColor: AppColors.background,
        isDense: true,
        radius: 24,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 13,
        ),
      ).copyWith(counterText: ''),
    );
  }
}

/// 둥근 핑크 보내기 버튼. 보낼 수 없을 때는 연하게, 보내는 중에는 로딩을 보여 준다.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.sending, required this.onPressed});

  final bool sending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: '보내기',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: enabled
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF08FA8), AppColors.primary],
                )
              : null,
          color: enabled ? null : AppColors.primaryLight,
          boxShadow: enabled ? softShadow : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('chatSendButton'),
            onTap: onPressed,
            child: Center(
              child: sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : Icon(
                      Icons.send_rounded,
                      size: 21,
                      color: enabled ? Colors.white : AppColors.primary,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
