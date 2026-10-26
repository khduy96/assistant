import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/entities/sync_budget.dart';
import 'sync_controller.dart';

/// Flips automatic sync on this device and says how it went — the tick in a
/// menu that has just closed is easy to miss.
///
/// The budget is the user's own, so the text never calls it a Back4App limit.
Future<void> toggleAutoSync(BuildContext context) async {
  final sync = context.read<SyncController>();
  final enable = !sync.autoSyncEnabled;
  final saved = await sync.setAutoSync(enable);
  if (!context.mounted) return;

  final message = !saved
      ? 'Không lưu được lựa chọn sync tự động, vẫn giữ như cũ.'
      : !enable
      ? 'Đã tắt sync tự động — vẫn dùng "Đồng bộ ngay" được.'
      : sync.budgetLevel == SyncBudgetLevel.exhausted
      ? 'Đã bật sync tự động — đã hết ngân sách request tháng này của máy '
            'này, sẽ tự chạy lại từ tháng sau.'
      : 'Đã bật sync tự động.';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
