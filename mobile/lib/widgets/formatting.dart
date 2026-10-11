/// Small formatting helpers. The project has no intl dependency yet.
abstract final class Formatting {
  /// `9:22`, or `1:02:05` for an hour or more.
  static String duration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
    }
    return '$minutes:$seconds';
  }

  /// `14:32`
  static String time(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// `Today`, `Yesterday` or `Mon 5 Oct`.
  static String day(DateTime value, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(value.year, value.month, value.day);
    final difference = today.difference(date).inDays;
    if (difference == 0) {
      return 'Today';
    }
    if (difference == 1) {
      return 'Yesterday';
    }
    final weekday = _weekdays[value.weekday - 1];
    final month = _months[value.month - 1];
    return '$weekday ${value.day} $month';
  }

  /// `1,203`
  static String count(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final fromEnd = digits.length - i;
      buffer.write(digits[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }

  /// `1 album`, `3 albums`
  static String albums(int count) => count == 1 ? '1 album' : '$count albums';
}
