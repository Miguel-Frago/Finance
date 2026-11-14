/// Pure attendance math (no Flutter, no database) so it can be unit tested.
///
/// Rules (change here if the company's rules differ):
///  - Late: if time in is later than start + grace, late = time in - start.
///  - Break: deducted from worked time when the person stayed 5 hours or more.
///  - Undertime: minutes left before the scheduled end.
///  - Overtime: minutes worked after the scheduled end.
///  - Overnight shifts are not supported yet.
class WorkSchedule {
  final int startMin, endMin, breakMin, graceMin;
  const WorkSchedule({
    required this.startMin,
    required this.endMin,
    required this.breakMin,
    required this.graceMin,
  });
}

class AttendanceResult {
  final int worked, lateMin, undertime, overtime;
  const AttendanceResult(this.worked, this.lateMin, this.undertime, this.overtime);
}

int parseHm(String hm) {
  final p = hm.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

String fmtHm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// "08:05" style minutes -> "8:05 AM"
String fmt12(int minutes) {
  final h = minutes ~/ 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${(minutes % 60).toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
}

/// 495 -> "8h 15m"
String fmtDuration(int minutes) => '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';

class AttendanceCalc {
  static const breakThresholdMin = 300;

  static AttendanceResult compute(WorkSchedule s, int timeIn, int? timeOut) {
    final lateMin = timeIn > s.startMin + s.graceMin ? timeIn - s.startMin : 0;
    if (timeOut == null) return AttendanceResult(0, lateMin, 0, 0);
    final gross = timeOut - timeIn;
    var worked = gross >= breakThresholdMin ? gross - s.breakMin : gross;
    if (worked < 0) worked = 0;
    final under = timeOut < s.endMin ? s.endMin - timeOut : 0;
    final over = timeOut > s.endMin ? timeOut - s.endMin : 0;
    return AttendanceResult(worked, lateMin, under, over);
  }
}
