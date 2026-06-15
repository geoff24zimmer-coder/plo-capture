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

/// Rank + suit glyph on a single line, four-colour, scaled to fit its box with a
/// [FittedBox] so it can NEVER wrap. This is the one place card text is composed
/// — every card in the app routes through here, so `Qd` and `Jd` (and the rest)
/// always lay the suit out the same way at every size.
Widget cardLabel(String card) => FittedBox(
      fit: BoxFit.contain,
      child: Text(
        '${card[0]}${suitGlyph(card[1])}',
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          height: 1.0,
          color: suitColor(card[1]),
        ),
      ),
    );

/// Canonical card face: a dark, rounded card showing [cardLabel]. [width] sets
/// the size; height follows the standard card ratio. Used on the felt, the
/// board, and the picker so every rendered card is identical.
class CardFace extends StatelessWidget {
  final String card; // e.g. 'Qd'
  final double width;
  const CardFace(this.card, {super.key, required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * 1.42,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(
          horizontal: width * 0.12, vertical: width * 0.16),
      decoration: BoxDecoration(
        color: const Color(0xF21A1E1B),
        borderRadius: BorderRadius.circular(width * 0.2),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.28), width: 0.6),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 2.5, offset: Offset(0, 1)),
        ],
      ),
      child: cardLabel(card),
    );
  }
}

/// Full-screen modal picker: returns exactly [count] card strings like 'As', or
/// null if cancelled. The drawer fills the screen, lays the four suits out as
/// vertical columns, and dismisses itself the moment the last card is picked.
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
    backgroundColor: const Color(0xFF0E100E),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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

  void _tap(String card) {
    if (selected.contains(card)) {
      setState(() => selected.remove(card));
      return;
    }
    if (selected.length >= widget.count) return;
    setState(() => selected.add(card));
    if (selected.length == widget.count) {
      // Selection complete — close after a brief beat so the last pick is seen.
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) Navigator.pop(context, List<String>.from(selected));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.97,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 44),
                  Expanded(
                    child: Text(
                      '${widget.title}   ${selected.length}/${widget.count}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, null),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Four suit columns, each a vertical strip of ranks that fills the
              // screen — big tap targets, the whole deck visible at once.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final suit in _suits)
                      Expanded(
                        child: Column(
                          children: [
                            for (final rank in _ranks)
                              Expanded(child: _cell('$rank$suit')),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(String card) {
    final used = widget.excluded.contains(card);
    final isSel = selected.contains(card);
    return Padding(
      padding: const EdgeInsets.all(2.5),
      child: GestureDetector(
        onTap: used ? null : () => _tap(card),
        child: Opacity(
          opacity: used ? 0.25 : 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              color: isSel
                  ? const Color(0x33EF9F27)
                  : Colors.white.withValues(alpha: 0.06),
              border: Border.all(
                width: isSel ? 2.5 : 0.8,
                color: isSel
                    ? const Color(0xFFEF9F27)
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
              child: cardLabel(card),
            ),
          ),
        ),
      ),
    );
  }
}
