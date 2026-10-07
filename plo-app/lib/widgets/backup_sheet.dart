import 'dart:convert';

import 'package:flutter/material.dart';

import '../db/hand_store.dart';
import '../export/download_web.dart';
import '../export/file_pick_web.dart';
import '../tracker/backup.dart';

/// Whole-device backup & restore, reached from the home screen. It covers
/// everything on this device — tracker sessions and logged hands — so it
/// belongs to neither feature. Browser storage is the only copy of a
/// player's history until there's cloud sync. [onRestored] runs after a
/// restore so the caller can refresh what it shows.
Future<void> showBackupSheet(BuildContext context,
    {VoidCallback? onRestored}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF0E100F),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Backup & restore',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
                'Your tracker sessions and logged hands live only in this '
                'browser. Download a backup now and then, and keep it '
                'somewhere safe.',
                style: TextStyle(
                    fontSize: 13, color: Colors.white.withValues(alpha: 0.6))),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.download),
              title: const Text('Download backup'),
              subtitle: const Text('Tracker + logged hands, to restore later'),
              onTap: () => Navigator.pop(ctx, 'backup'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restore),
              title: const Text('Restore from backup'),
              subtitle: const Text('Adds to what’s here; never overwrites'),
              onTap: () => Navigator.pop(ctx, 'restore'),
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case 'backup':
      await _download(context);
    case 'restore':
      if (await _restore(context)) onRestored?.call();
  }
}

String _stamp() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${n.year}-${two(n.month)}-${two(n.day)}';
}

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

Future<void> _download(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final doc = await HandStore.instance.exportAll();
  downloadText('plo-show-backup_${_stamp()}.json', jsonEncode(doc));
  messenger.showSnackBar(const SnackBar(
      content: Text('Backup downloaded — keep it somewhere safe.')));
}

/// Pick, validate, confirm and merge a backup. True if anything was restored.
Future<bool> _restore(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final String? text;
  try {
    text = await pickTextFile();
  } catch (_) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t read that file.')));
    return false;
  }
  if (text == null || !context.mounted) return false;
  final BackupData data;
  try {
    data = parseBackup(text);
  } on FormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Restore backup?'),
      content: Text(
          'Adds ${_count(data.trackerSessions.length, 'tracker session')} '
          'and ${_count(data.hands.length, 'logged hand')}. Anything '
          'already on this device is kept as-is.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore')),
      ],
    ),
  );
  if (yes != true) return false;
  final r = await HandStore.instance.importBackup(data);
  messenger.showSnackBar(SnackBar(
      content: Text('Restored '
          '${_count(r.trackerAdded, 'tracker session')}, '
          '${_count(r.handsAdded, 'logged hand')}'
          '${r.skipped > 0 ? ' (${r.skipped} already here)' : ''}.')));
  return true;
}
