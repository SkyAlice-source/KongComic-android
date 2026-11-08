import 'package:kong_comic/utils/ext.dart';

enum ImageFavoriteSortType {
  title("Title"),
  timeAsc("Time Asc"),
  timeDesc("Time Desc"),
  maxFavorites("Favorite Num"), // 单本收藏数最多排序
  favoritesCompareComicPages("Favorite Num Compare Comic Pages"); // 单本收藏数比上总页数

  final String value;

  const ImageFavoriteSortType(this.value);
}

const numFilterList = [0, 1, 2, 5, 10, 20, 50, 100];

class TimeRange {
  /// End of the range, null means now
  final DateTime? end;

  /// Duration of the range
  final Duration duration;

  /// Create a time range
  const TimeRange({this.end, required this.duration});

  static const all = TimeRange(end: null, duration: Duration.zero);

  static const lastWeek = TimeRange(end: null, duration: Duration(days: 7));

  static const lastMonth = TimeRange(end: null, duration: Duration(days: 30));

  static const lastHalfYear = TimeRange(
    end: null,
    duration: Duration(days: 180),
  );

  static const lastYear = TimeRange(end: null, duration: Duration(days: 365));

  @override
  String toString() {
    return "${end?.millisecondsSinceEpoch}:${duration.inMilliseconds}";
  }

  /// Parse a time range from a string, return [TimeRange.all] if failed
  factory TimeRange.fromString(String? str) {
    if (str == null) {
      return TimeRange.all;
    }
    final parts = str.split(":");
    if (parts.length != 2) {
      return TimeRange.all;
    }
    // "null" 是合法前缀：预设区间（lastWeek / lastMonth / ...）的 end 都是
    // null，toString 出来就是 "null:604800000"。旧实现先要求 parts[0] 是整数，
    // 于是这些串全部退回 all —— 用户设了「最近一周」，重启后筛选悄悄消失。
    DateTime? end;
    if (parts[0] != "null") {
      if (!parts[0].isInt) return TimeRange.all;
      end = DateTime.fromMillisecondsSinceEpoch(int.parse(parts[0]));
    }
    if (!parts[1].isInt) {
      return TimeRange.all;
    }
    final duration = Duration(milliseconds: int.parse(parts[1]));
    return TimeRange(end: end, duration: duration);
  }

  /// Check if a time is in the range
  bool contains(DateTime time) {
    if (end != null && time.isAfter(end!)) {
      return false;
    }
    if (duration == Duration.zero) {
      return true;
    }
    final start = end == null
        ? DateTime.now().subtract(duration)
        : end!.subtract(duration);
    return time.isAfter(start);
  }

  @override
  bool operator ==(Object other) {
    return other is TimeRange && other.end == end && other.duration == duration;
  }

  @override
  int get hashCode => end.hashCode ^ duration.hashCode;

  static const List<TimeRange> values = [
    all,
    lastWeek,
    lastMonth,
    lastHalfYear,
    lastYear,
  ];
}

enum TimeRangeType {
  all("All"),
  lastWeek("Last Week"),
  lastMonth("Last Month"),
  lastHalfYear("Last Half Year"),
  lastYear("Last Year"),
  custom("Custom");

  final String value;

  const TimeRangeType(this.value);
}
