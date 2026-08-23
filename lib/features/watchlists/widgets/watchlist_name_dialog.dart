import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../data/repositories/watchlist_repository.dart';

/// Prompts for a watchlist name. Used for both create and rename.
///
/// Returns the entered name, or `null` if the user cancelled. Validation of
/// duplicates and limits stays in the notifier — this dialog only guards
/// against submitting nothing, which is a keyboard-level concern.
class WatchlistNameDialog extends StatefulWidget {
  const WatchlistNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initialValue = '',
    super.key,
  });

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    String initialValue = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => WatchlistNameDialog(
        title: title,
        confirmLabel: confirmLabel,
        initialValue: initialValue,
      ),
    );
  }

  final String title;
  final String confirmLabel;
  final String initialValue;

  @override
  State<WatchlistNameDialog> createState() => _WatchlistNameDialogState();
}

class _WatchlistNameDialogState extends State<WatchlistNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainer,
      title: Text(widget.title, style: AppTypography.titleSm),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: WatchlistRepository.maxNameLength,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        style: AppTypography.bodyMd,
        decoration: const InputDecoration(
          hintText: 'Watchlist name',
          counterStyle: TextStyle(color: AppColors.muted),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        // Enabled state tracks the field so the primary action is never a
        // no-op tap.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (BuildContext context, TextEditingValue value, _) {
            return FilledButton(
              onPressed: value.text.trim().isEmpty ? null : _submit,
              child: Text(widget.confirmLabel),
            );
          },
        ),
      ],
    );
  }
}
