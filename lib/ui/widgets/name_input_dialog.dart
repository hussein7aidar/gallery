import 'package:flutter/material.dart';

/// A single-text-field dialog whose [TextEditingController] is owned by the
/// dialog's own State, so it is disposed only after the route is fully gone.
/// (Disposing a controller right after `await showDialog` crashes, because the
/// dialog rebuilds during its close animation.)
///
/// Returns the entered text, or null if cancelled.
Future<String?> showNameInputDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String confirmLabel = 'Save',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameInputDialog(
      title: title,
      initialValue: initialValue,
      confirmLabel: confirmLabel,
    ),
  );
}

class _NameInputDialog extends StatefulWidget {
  const _NameInputDialog({
    required this.title,
    required this.initialValue,
    required this.confirmLabel,
  });

  final String title;
  final String initialValue;
  final String confirmLabel;

  @override
  State<_NameInputDialog> createState() => _NameInputDialogState();
}

class _NameInputDialogState extends State<_NameInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
