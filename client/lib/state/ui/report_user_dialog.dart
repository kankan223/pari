import 'package:flutter/material.dart';

import '../../repository/data/blocking_service.dart';
import 'vault_theme.dart';

/// Shows a report dialog for a user. Returns true if the report was filed.
Future<bool> showReportDialog({
  required BuildContext context,
  required BlockingService blockingService,
  required String targetHashId,
}) async {
  ReportReason? selectedReason;
  final detailsController = TextEditingController();

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.flag_outlined, color: Colors.red),
            SizedBox(width: 8),
            Text('Report User'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Why are you reporting this user?',
                style: TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              ...ReportReason.values.map((reason) => RadioListTile<ReportReason>(
                    value: reason,
                    groupValue: selectedReason,
                    onChanged: (v) => setDialogState(() => selectedReason = v),
                    title: Text(reason.label, style: const TextStyle(fontSize: 14)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  )),
              const SizedBox(height: 8),
              TextField(
                controller: detailsController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Additional details (optional)',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: selectedReason == null
                ? null
                : () async {
                    await blockingService.report(
                      blindHashId: targetHashId,
                      reason: selectedReason!.name,
                      details: detailsController.text,
                    );
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Submit Report'),
          ),
        ],
      ),
    ),
  );

  detailsController.dispose();
  return result ?? false;
}

/// Shows a block confirmation dialog. Returns true if the user was blocked.
Future<bool> showBlockDialog({
  required BuildContext context,
  required BlockingService blockingService,
  required String targetHashId,
  String? targetUsername,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.block, color: Colors.red),
          SizedBox(width: 8),
          Text('Block User'),
        ],
      ),
      content: Text(
        targetUsername != null
            ? 'Block @$targetUsername? They won\'t be able to send you messages.'
            : 'Block this user? They won\'t be able to send you messages.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Block'),
        ),
      ],
    ),
  );

  if (result == true) {
    await blockingService.block(targetHashId);
  }
  return result ?? false;
}
