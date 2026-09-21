import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/clip_item.dart';
import '../state/clipboard_store.dart';
import '../sync/sync_service.dart';
import 'clip_actions.dart';
import 'format.dart';
import 'group_detail_page.dart';
import 'widgets/clip_card.dart';
import 'widgets/clip_list.dart';
import 'widgets/selection_bar.dart';

/// The four lists inside the clipboard tab.
enum ClipboardSection {
  temp('Tạm', Icons.history_rounded),
  saved('Đã lưu', Icons.bookmark_rounded),
  pinned('Ghim', Icons.push_pin_rounded),
  groups('Nhóm', Icons.folder_rounded);

  const ClipboardSection(this.label, this.icon);

  final String label;
  final IconData icon;

  int countIn(ClipboardStore store) => switch (this) {
        ClipboardSection.temp => store.tempCount,
        ClipboardSection.saved => store.savedCount,
        ClipboardSection.pinned => store.pinnedCount,
        ClipboardSection.groups => store.groups.length,
      };
}

/// What the clipboard tab remembers: the search box and which list is open.
///
/// It lives above the tab because the app bar and the floating button belong
/// to the shared scaffold and have to follow the section — and because one
/// query serves all four lists, so switching them keeps what was typed.
class ClipboardTabState extends ChangeNotifier {
  final TextEditingController search = TextEditingController();

  ClipboardSection _section = ClipboardSection.temp;
  ClipboardSection get section => _section;

  void goTo(ClipboardSection value) {
    if (_section == value) return;
    _section = value;
    notifyListeners();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }
}

/// The clipboard, as one tab of the app: its own bar of four lists, the search
/// box under it, and the list itself.
///
/// The standalone app put these four in a bottom navigation bar; here they sit
/// inside the tab so the top bar keeps one entry per part of the app.
class ClipboardTab extends StatefulWidget {
  const ClipboardTab({super.key});

  @override
  State<ClipboardTab> createState() => _ClipboardTabState();
}

class _ClipboardTabState extends State<ClipboardTab>
    with SingleTickerProviderStateMixin {
  late final TabController _inner = TabController(
    length: ClipboardSection.values.length,
    vsync: this,
    initialIndex: context.read<ClipboardTabState>().section.index,
  )..addListener(_onTabChanged);

  @override
  void dispose() {
    _inner.removeListener(_onTabChanged);
    _inner.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_inner.indexIsChanging) return;
    final section = ClipboardSection.values[_inner.index];
    if (section == context.read<ClipboardTabState>().section) return;
    // The selection belonged to the list being left behind.
    context.read<ClipboardStore>().clearSelection();
    context.read<ClipboardTabState>().goTo(section);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClipboardStore>();
    if (store.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final section = context.watch<ClipboardTabState>().section;

    return PopScope(
      // Back leaves multi-select before it leaves the app.
      canPop: !store.isSelecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) store.clearSelection();
      },
      child: Column(
        children: [
          TabBar.secondary(
            controller: _inner,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final s in ClipboardSection.values)
                Tab(
                  icon: Icon(s.icon, size: 20),
                  text: switch (s.countIn(store)) {
                    0 => s.label,
                    final count => '${s.label} ($count)',
                  },
                ),
            ],
          ),
          store.isSelecting
              ? _SelectionHeader(items: visibleItems(store, section))
              : _SearchRow(section: section),
          Expanded(
            child: TabBarView(
              controller: _inner,
              children: [
                for (final s in ClipboardSection.values) _SectionList(section: s),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The clips a section is showing — what "chọn tất cả" applies to.
List<ClipItem> visibleItems(ClipboardStore store, ClipboardSection section) =>
    switch (section) {
      ClipboardSection.temp => store.tempClips,
      ClipboardSection.saved => store.savedClips,
      ClipboardSection.pinned => store.pinnedClips,
      ClipboardSection.groups => store.ungroupedSaved,
    };

/// One section's list, without the bar and the search box above it.
class _SectionList extends StatelessWidget {
  const _SectionList({required this.section});

  final ClipboardSection section;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClipboardStore>();
    return CustomScrollView(slivers: [_sectionSliver(context, store)]);
  }

  Widget _sectionSliver(BuildContext context, ClipboardStore store) {
    switch (section) {
      case ClipboardSection.temp:
        return ClipSliver(
          items: store.tempClips,
          emptyIcon: Icons.content_paste_rounded,
          emptyTitle: 'Chưa có gì trong bộ nhớ tạm',
          emptyHint: 'Copy bất cứ đoạn văn bản nào, nó sẽ xuất hiện ở đây và '
              'tự xoá sau 1 ngày.',
        );
      case ClipboardSection.saved:
        return ClipSliver(
          items: store.savedClips,
          emptyIcon: Icons.bookmark_border_rounded,
          emptyTitle: 'Danh sách lưu đang trống',
          emptyHint:
              'Vuốt một clip ở tab Tạm sang phải, hoặc giữ để chọn "Lưu".',
        );
      case ClipboardSection.pinned:
        return ClipSliver(
          items: store.pinnedClips,
          emptyIcon: Icons.push_pin_outlined,
          emptyTitle: 'Chưa ghim clip nào',
          emptyHint: 'Ghim một clip tạm thì nó sẽ tự động được lưu lại.',
        );
      case ClipboardSection.groups:
        return const _GroupsSliver();
    }
  }
}

/// The floating button for a clipboard tab.
Widget clipboardFab(BuildContext context, ClipboardSection section) {
  if (section == ClipboardSection.groups) {
    return FloatingActionButton.extended(
      onPressed: () => showGroupEditor(context),
      icon: const Icon(Icons.create_new_folder_outlined),
      label: const Text('Nhóm mới'),
    );
  }
  return FloatingActionButton.extended(
    onPressed: () => editClip(context, null),
    icon: const Icon(Icons.add_rounded),
    label: const Text('Thêm clip'),
  );
}

/// App bar buttons that only make sense while a clipboard tab is open.
List<Widget> clipboardActions(BuildContext context, ClipboardSection section) {
  final store = context.watch<ClipboardStore>();
  return [
    const _CaptureButton(),
    const _SyncButton(),
    if (section == ClipboardSection.temp)
      IconButton(
        tooltip: 'Xoá hết mục tạm',
        icon: const Icon(Icons.delete_sweep_outlined),
        onPressed:
            store.tempCount == 0 ? null : () => _confirmClear(context, store),
      ),
  ];
}

Future<void> _confirmClear(BuildContext context, ClipboardStore store) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Xoá hết mục tạm?'),
      content: const Text('Các clip đã lưu và đã ghim vẫn được giữ nguyên.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Xoá'),
        ),
      ],
    ),
  );
  if (ok == true) await store.clearTemp();
}

/// Recording toggle: the clipboard is only watched while this is on.
class _CaptureButton extends StatelessWidget {
  const _CaptureButton();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClipboardStore>();
    final on = store.captureEnabled;
    return IconButton(
      tooltip:
          on ? 'Đang ghi clipboard — chạm để dừng' : 'Đã dừng — chạm để ghi',
      onPressed: () => store.setCaptureEnabled(!on),
      icon: Icon(
        on
            ? Icons.fiber_manual_record_rounded
            : Icons.pause_circle_outline_rounded,
        color:
            on ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Sync state at a glance: spins while running, turns red on the last error.
class _SyncButton extends StatelessWidget {
  const _SyncButton();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClipboardStore>();
    final status = store.syncStatus;
    final scheme = Theme.of(context).colorScheme;

    if (status.isRunning) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final configured = store.config.isConfigured;
    final failed = status.state == SyncState.error;
    return IconButton(
      tooltip: switch (status.state) {
        SyncState.notConfigured =>
          'Chưa cấu hình — build với --dart-define-from-file=.env để bật đồng bộ',
        SyncState.error => 'Đồng bộ lỗi: ${status.message}',
        SyncState.ok => status.lastSyncAt == null
            ? 'Đồng bộ ngay'
            : 'Đồng bộ lần cuối ${formatRelative(status.lastSyncAt!)}'
                ' · đẩy ${status.pushed}, nhận ${status.pulled}',
        _ => 'Đồng bộ ngay (${store.config.space})',
      },
      icon: Icon(
        configured
            ? (failed ? Icons.cloud_off_rounded : Icons.cloud_sync_outlined)
            : Icons.cloud_off_rounded,
        color: failed ? scheme.error : null,
      ),
      // Nothing to open when unconfigured: the .env has to change at build time.
      onPressed: configured ? () => runSync(context) : null,
    );
  }
}

/// Search box plus the type filter, sitting above the list.
class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.section});

  final ClipboardSection section;

  @override
  Widget build(BuildContext context) {
    final store = context.read<ClipboardStore>();
    final controller = context.read<ClipboardTabState>().search;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => TextField(
                controller: controller,
                onChanged: store.setQuery,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Tìm trong clipboard…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: value.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            controller.clear();
                            store.setQuery('');
                          },
                        ),
                  isDense: true,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          if (section != ClipboardSection.groups) ...[
            const SizedBox(width: 8),
            const _FilterButton(),
          ],
        ],
      ),
    );
  }
}

/// Type filter as a sheet: the chip row never fit next to eight tabs.
class _FilterButton extends StatelessWidget {
  const _FilterButton();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClipboardStore>();
    final active = store.typeFilter;
    final scheme = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      tooltip: active == null ? 'Lọc theo loại' : 'Đang lọc: ${active.label}',
      onPressed: () => _show(context, store),
      icon: Badge(
        isLabelVisible: active != null,
        smallSize: 8,
        backgroundColor: scheme.primary,
        child: Icon(active?.icon ?? Icons.filter_list_rounded),
      ),
    );
  }

  Future<void> _show(BuildContext context, ClipboardStore store) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.done_all_rounded),
              title: const Text('Tất cả loại'),
              trailing: store.typeFilter == null
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () {
                store.setTypeFilter(null);
                Navigator.pop(sheetContext);
              },
            ),
            for (final type in ClipType.values)
              ListTile(
                leading: Icon(type.icon),
                title: Text(type.label),
                trailing: store.typeFilter == type
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () {
                  store.setTypeFilter(type);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// What the app bar used to turn into while clips are selected.
///
/// The app bar is shared with the reminder tabs now, so the selection UI sits
/// inside the tab instead of taking the bar over.
class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader({required this.items});

  final List<ClipItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bar = SelectionBar(items);
    return Material(
      color: scheme.primaryContainer,
      child: IconTheme(
        data: IconThemeData(color: scheme.onPrimaryContainer),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: scheme.onPrimaryContainer),
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                bar.leading(context),
                const SizedBox(width: 4),
                Expanded(child: bar.title(context)),
                ...bar.actions(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupsSliver extends StatelessWidget {
  const _GroupsSliver();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClipboardStore>();
    final groups = store.groups;
    final ungrouped = store.ungroupedSaved;

    if (groups.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.folder_open_rounded,
          title: 'Chưa có nhóm nào',
          hint: 'Tạo nhóm để gom các clip cùng loại: link, mã OTP, mẫu câu…',
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
          12, 4, 12, 96 + MediaQuery.paddingOf(context).bottom),
      sliver: SliverList.list(
        children: [
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        group.materialColor.withValues(alpha: 0.18),
                    child:
                        Icon(Icons.folder_rounded, color: group.materialColor),
                  ),
                  title: Text(group.name),
                  subtitle: Text('${store.countOfGroup(group.id)} clip'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GroupDetailPage(groupId: group.id),
                    ),
                  ),
                ),
              ),
            ),
          if (ungrouped.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text('Đã lưu, chưa phân nhóm (${ungrouped.length})',
                  style: Theme.of(context).textTheme.labelLarge),
            ),
            for (final item in ungrouped)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipCard(item: item),
              ),
          ],
        ],
      ),
    );
  }
}
