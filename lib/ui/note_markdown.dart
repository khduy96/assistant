import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// GitHub flavour: tables, strikethrough, fenced code and auto-links. This is
/// what people expect when they type Markdown into a note.
final md.ExtensionSet noteMarkdownExtensions = md.ExtensionSet.gitHubWeb;

/// Renders a note body as Markdown, with tappable links.
///
/// Lives on its own so the read-only page and the editor preview show exactly
/// the same thing.
class NoteMarkdown extends StatelessWidget {
  const NoteMarkdown({super.key, required this.data, this.selectable = true});

  final String data;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return MarkdownBody(
      data: data,
      selectable: selectable,
      extensionSet: noteMarkdownExtensions,
      onTapLink: (text, href, title) => _openLink(context, href),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        a: TextStyle(
          color: scheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: scheme.primary,
        ),
        code: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) - 1,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(color: scheme.primary, width: 4),
          ),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: scheme.outlineVariant, width: 1),
          ),
        ),
        tableBorder: TableBorder.all(color: scheme.outlineVariant),
        tableHead: const TextStyle(fontWeight: FontWeight.w600),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        // An intrinsic width makes the package wrap wide tables in a
        // horizontal scroller instead of squeezing the columns.
        tableColumnWidth: const IntrinsicColumnWidth(),
      ),
    );
  }
}

/// Opens [href] in the system browser (or mail client, etc.).
///
/// A bare `example.com` has no scheme, so `https://` is filled in — otherwise
/// the platform refuses to launch it.
Future<void> _openLink(BuildContext context, String? href) async {
  final raw = href?.trim() ?? '';
  if (raw.isEmpty) return;

  var uri = Uri.tryParse(raw);
  if (uri != null && !uri.hasScheme) uri = Uri.tryParse('https://$raw');

  final ok = uri != null &&
      await launchUrl(uri, mode: LaunchMode.externalApplication)
          .catchError((_) => false);

  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Không mở được liên kết: $raw')),
    );
  }
}
