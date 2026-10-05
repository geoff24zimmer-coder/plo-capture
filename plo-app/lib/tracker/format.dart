/// Tracker display + input helpers. Tracker money is always real currency in
/// cents (even for MTT sessions), so these never consult the global chipMode.
library;

String _group(int v) =>
    v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

/// Cents → "$1,240" / "$12.50"; [signed] adds "+" to positives.
String usd(int cents, {bool signed = false}) {
  final sign = cents < 0 ? '-' : (signed && cents > 0 ? '+' : '');
  final v = cents.abs();
  final rem = v % 100;
  return rem == 0
      ? '$sign\$${_group(v ~/ 100)}'
      : '$sign\$${_group(v ~/ 100)}.${rem.toString().padLeft(2, '0')}';
}

/// Compact signed whole dollars for calendar cells: "+420", "-1.2k", "+15k".
String usdCompact(int cents) {
  final d = (cents / 100).round();
  final sign = d < 0 ? '-' : '+';
  final a = d.abs();
  if (a < 1000) return '$sign$a';
  final k = a / 1000;
  return '$sign${k < 10 ? k.toStringAsFixed(1).replaceAll('.0', '') : k.round()}k';
}

/// Cents per hour → "$42/hr" (whole dollars; rates aren't that precise).
String usdRate(double? centsPerHour) {
  if (centsPerHour == null) return '—';
  return '${usd((centsPerHour / 100).round() * 100)}/hr';
}

/// 3.25 → "3.3" (calendar HRS box) — one decimal, trailing ".0" dropped.
String hoursShort(double h) {
  final s = h.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Duration → "3h 25m" / "45m".
String durationLabel(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h == 0 ? '${m}m' : '${h}h ${m.toString().padLeft(2, '0')}m';
}

/// User-typed dollars → cents. Accepts "1500", "1,500", "$1,500.5", " 20 ".
/// Null for blank or unparseable input (so the field reads as "not entered").
int? parseDollars(String text) {
  final t = text.replaceAll(RegExp(r'[\s,$]'), '');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v.isNaN || v.isInfinite || v < 0) return null;
  return (v * 100).round();
}

/// Cents → an editable field value: "1500" / "12.5" (no symbol, no commas).
String dollarsField(int? cents) {
  if (cents == null) return '';
  if (cents % 100 == 0) return '${cents ~/ 100}';
  return (cents / 100).toStringAsFixed(2);
}

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

String shortDate(DateTime d) => '${monthNames[d.month - 1].substring(0, 3)} ${d.day}';

String clock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')}${d.hour < 12 ? 'am' : 'pm'}';
}
