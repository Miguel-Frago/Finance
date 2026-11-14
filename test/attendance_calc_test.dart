import 'package:flutter_test/flutter_test.dart';
import 'package:bfm_app/core/attendance_calc.dart';

void main() {
  const s8to5 = WorkSchedule(startMin: 480, endMin: 1020, breakMin: 60, graceMin: 0);
  const withGrace = WorkSchedule(startMin: 480, endMin: 1020, breakMin: 60, graceMin: 10);

  test('full day on time', () {
    final r = AttendanceCalc.compute(s8to5, 480, 1020);
    expect([r.worked, r.lateMin, r.undertime, r.overtime], [480, 0, 0, 0]);
  });

  test('late and early out', () {
    final r = AttendanceCalc.compute(s8to5, 495, 990); // 8:15 to 4:30
    expect([r.worked, r.lateMin, r.undertime, r.overtime], [435, 15, 30, 0]);
  });

  test('overtime', () {
    final r = AttendanceCalc.compute(s8to5, 480, 1110); // out 6:30 PM
    expect([r.worked, r.lateMin, r.undertime, r.overtime], [570, 0, 0, 90]);
  });

  test('grace period', () {
    expect(AttendanceCalc.compute(withGrace, 490, null).lateMin, 0); // 8:10
    expect(AttendanceCalc.compute(withGrace, 491, null).lateMin, 11); // 8:11
  });

  test('short stay does not deduct break', () {
    final r = AttendanceCalc.compute(s8to5, 480, 660); // 3 hours
    expect(r.worked, 180);
  });

  test('no time out yet', () {
    final r = AttendanceCalc.compute(s8to5, 480, null);
    expect([r.worked, r.undertime, r.overtime], [0, 0, 0]);
  });
}
