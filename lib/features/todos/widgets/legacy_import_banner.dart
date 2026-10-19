import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// 서버 연결 전에 이 브라우저에 저장한 할 일이 있을 때 가져오기를 안내한다.
class LegacyImportBanner extends StatelessWidget {
  const LegacyImportBanner({
    super.key,
    required this.count,
    required this.importing,
    required this.onDismiss,
    required this.onImport,
  });

  final int count;

  /// 가져오는 중이면 버튼을 막고 진행 표시를 보여 준다.
  final bool importing;
  final VoidCallback onDismiss;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('legacyBanner'),
      elevation: 0,
      color: AppColors.warningBackground,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  color: Color(0xFFD97706),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '서버 연결 전에 이 브라우저에 저장한 할 일 $count개가 있습니다. '
                    '자동으로 옮겨지지 않으며, 가져오면 현재 계정에 저장됩니다.',
                    style: const TextStyle(
                      color: AppColors.textMain,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: importing ? null : onDismiss,
                    child: const Text('나중에'),
                  ),
                  TextButton(
                    onPressed: importing ? null : onImport,
                    child: importing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('서버로 가져오기'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
