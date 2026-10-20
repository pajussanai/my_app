// 실제 브라우저에서 채팅 입력창의 키보드 동작(Enter, Shift+Enter, 한글 입력)을
// 직접 확인하는 화면. 로그인·서버 없이 열리며 앱 빌드에는 포함되지 않는다.
//
// 실행:
//   flutter run -d chrome --web-port 3001 -t tool/composer_playground.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:my_app/app/theme.dart';
import 'package:my_app/features/chat/widgets/message_composer.dart';

void main() => runApp(const _PlaygroundApp());

class _PlaygroundApp extends StatelessWidget {
  const _PlaygroundApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '입력창 확인',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const _Playground(),
    );
  }
}

class _Playground extends StatefulWidget {
  const _Playground();

  @override
  State<_Playground> createState() => _PlaygroundState();
}

class _PlaygroundState extends State<_Playground> {
  final _sent = <String>[];
  bool _sending = false;
  bool _slowReply = false;

  Future<bool> _onSend(String text) async {
    setState(() {
      _sent.add(text);
      _sending = _slowReply;
    });
    if (_slowReply) {
      // 답변을 받는 중인 상태를 3초 동안 흉내 낸다(이때 Enter로 다시 보내지면 안 된다).
      unawaited(
        Future<void>.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _sending = false);
        }),
      );
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('입력창 키보드 확인')),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text('보낸 뒤 3초 동안 "답변 받는 중" 상태로 두기'),
            value: _slowReply,
            onChanged: (v) => setState(() => _slowReply = v),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '보낸 메시지가 아래에 그대로 표시됩니다. 줄바꿈은 ⏎, 앞뒤 공백은 ·로 보입니다. '
              '마지막 글자가 빠지거나 두 번 보내지지 않는지 확인하세요.',
              style: TextStyle(color: AppColors.textSub),
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _sent.length,
              itemBuilder: (context, i) {
                final text = _sent[i];
                final shown = text
                    .replaceAll('\n', '⏎')
                    .replaceAll(RegExp(r'^ +| +$'), '·');
                return ListTile(
                  dense: true,
                  leading: Text('#${i + 1}'),
                  title: Text(shown),
                  subtitle: Text('${text.length}자'),
                );
              },
            ),
          ),
          MessageComposer(sending: _sending, onSend: _onSend),
        ],
      ),
    );
  }
}
