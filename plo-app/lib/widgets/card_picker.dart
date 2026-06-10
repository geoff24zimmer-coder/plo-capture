import 'package:flutter/material.dart';

/// Four-color deck — at a glance suit reads matter in PLO.
const _suits = ['s', 'h', 'd', 'c'];
const _ranks = ['A', 'K', 'Q', 'J', 'T', '9', '8', '7', '6', '5', '4', '3', '2'];

Color suitColor(String suit) => switch (suit) {
      'h' => const Color(0xFFE24B4A),
      'd' => const Color(0xFF378ADD),
      'c' => const Color(0xFF63B944),
      _ => const Color(0xFFE8E6E1), // spades
    };

String suitGlyph(String suit) =>
    switch (suit) { 'h' => '♥', 'd' => '♦', 'c' => '♣', _ => '♠' };

/// Modal picker: returns exactly [count] card strings like 'As', or null.
Future<List<String>?> pickCards(
  BuildContext context, {
  required int count,
  required Set<String> excluded,
  required String title,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    builder: (_) =>
        _CardPickerSheet(count: count, excluded: excluded, title: title),
  );
}

class _CardPickerSheet extends StatefulWidget {
  final int count;
  final Set<String> excluded;
  final String title;
  const _CardPickerSheet(
      {required this.count, required this.excluded, required this.title});

  @override
  State<_CardPickerSheet> createState() => _CardPickerSheetState();
}

class _CardPickerSheetState extends State<_CardPickerSheet> {
  final List<String> selected = [];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.title}  (${selected.length}/${widget.count})',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            for (final suit in _suits) ...[
              Row(
                children: [
                  for (final rank in _ranks)
                    Expanded(child: _cell('$rank$suit')),
                ],
              ),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: selected.length == widget.count
                  ? () => Navigator.pop(context, List<String>.from(selected))
                  : null,
              child: Text('Confirm ${selected.join(' ')}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(String card) {
    final used = widget.excluded.contains(card);
    final isSel = selected.contains(card);
    final suit = card[1];
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: InkWell(
        onTap: used
            ? null
            : () => setState(() {
                  if (isSel) {
                    selected.remove(card);
                  } else if (selected.length < widget.count) {
                    selected.add(card);
                  }
                }),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              width: isSel ? 2 : 0.5,
              color: isSel
                  ? const Color(0xFFEF9F27)
                  : Colors.white.withValues(alpha: 0.15),
            ),
            color: used
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.white.withValues(alpha: 0.08),
          ),
          child: Opacity(
            opacity: used ? 0.25 : 1,
            child: Text(
              '${card[0]}${suitGlyph(suit)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: suitColor(suit),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
