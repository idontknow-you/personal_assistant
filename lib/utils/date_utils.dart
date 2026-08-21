/// Formats a DateTime as a "yyyy-MM-dd" key — used to index completion
/// logs and other per-day data. Local calendar day only, no time
/// component, so it's stable regardless of what time a task was toggled.
String dateKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

DateTime startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Time-of-day greeting: "Good morning, Alice" etc.
String greetingForName(String name) {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning, $name';
  if (hour < 17) return 'Good afternoon, $name';
  return 'Good evening, $name';
}