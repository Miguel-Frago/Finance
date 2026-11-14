import 'package:flutter_test/flutter_test.dart';
import 'package:bfm_app/core/payroll_calc.dart';

void main() {
  const s = PayrollSettings(
      stdMinutes: 480, daysFactor: 261, workWeekdays: {1, 2, 3, 4, 5}, otMultiplier: 1.25);
  const full = AttDay(workedMin: 480, overtimeMin: 0, lateMin: 0, complete: true);

  test('daily rate: full day, short day, overtime day', () {
    final r = PayrollCalc.compute(
      PayrollCalcInput(
        from: DateTime(2026, 11, 2),
        to: DateTime(2026, 11, 4),
        hired: DateTime(2026, 1, 1),
        today: DateTime(2026, 12, 1),
        entries: const [RateEntry('2026-01-01', 'Daily', 80000)],
        attendance: {
          '2026-11-02': full,
          '2026-11-03': const AttDay(workedMin: 435, overtimeMin: 0, lateMin: 15, complete: true),
          '2026-11-04': const AttDay(workedMin: 570, overtimeMin: 90, lateMin: 0, complete: true),
        },
      ),
      s,
    );
    expect(r.basic, 232500); // 800 + 725 + 800 pesos
    expect(r.overtime, 18750); // 90 min x (800/480) x 1.25
    expect(r.daysWorked, 3);
    expect(r.overtimeMin, 90);
  });

  test('monthly rate, full month, no absences counted yet', () {
    final r = PayrollCalc.compute(
      PayrollCalcInput(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
        hired: DateTime(2026, 1, 1),
        today: DateTime(2026, 10, 1),
        entries: const [RateEntry('2026-01-01', 'Monthly', 3100000)],
        attendance: const {},
      ),
      s,
    );
    expect(r.basic, 3100000);
    expect(r.absentDays, 0);
  });

  test('monthly rate: one absent working day', () {
    final att = {
      for (final d in ['2026-10-05', '2026-10-06', '2026-10-07', '2026-10-08']) d: full,
    };
    final r = PayrollCalc.compute(
      PayrollCalcInput(
        from: DateTime(2026, 10, 5),
        to: DateTime(2026, 10, 9),
        hired: DateTime(2026, 1, 1),
        today: DateTime(2026, 10, 20),
        entries: const [RateEntry('2026-01-01', 'Monthly', 3100000)],
        attendance: att,
      ),
      s,
    );
    expect(r.basic, 500000); // 5 days x 1,000
    expect(r.absentDays, 1);
    expect(r.absenceDed, 142529); // 31,000 x 12 / 261 = 1,425.29
  });

  test('hired mid-period only accrues from the hire date', () {
    final r = PayrollCalc.compute(
      PayrollCalcInput(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
        hired: DateTime(2026, 10, 16),
        today: DateTime(2026, 10, 1),
        entries: const [RateEntry('2026-10-16', 'Monthly', 3100000)],
        attendance: const {},
      ),
      s,
    );
    expect(r.basic, 1600000); // 16 days x 1,000
  });

  test('missing time out gives a warning and no daily pay', () {
    final r = PayrollCalc.compute(
      PayrollCalcInput(
        from: DateTime(2026, 11, 2),
        to: DateTime(2026, 11, 2),
        hired: DateTime(2026, 1, 1),
        today: DateTime(2026, 12, 1),
        entries: const [RateEntry('2026-01-01', 'Daily', 80000)],
        attendance: const {
          '2026-11-02': AttDay(workedMin: 0, overtimeMin: 0, lateMin: 0, complete: false)
        },
      ),
      s,
    );
    expect(r.basic, 0);
    expect(r.warnings.length, 1);
  });

  PayrollCalcInput one(String type, int rate, DateTime day,
      {Map<String, AttDay> att = const {}, Map<String, String> hol = const {}, Set<String> leave = const {}}) {
    return PayrollCalcInput(
      from: day,
      to: day,
      hired: DateTime(2026, 1, 1),
      today: DateTime(2026, 12, 1),
      entries: [RateEntry('2026-01-01', type, rate)],
      attendance: att,
      holidays: hol,
      paidLeave: leave,
    );
  }

  test('worked on a regular holiday: +100% premium', () {
    final r = PayrollCalc.compute(
        one('Daily', 80000, DateTime(2026, 11, 2),
            att: {'2026-11-02': full}, hol: {'2026-11-02': 'Regular'}),
        s);
    expect(r.basic, 80000);
    expect(r.holidayPremium, 80000);
  });

  test('daily staff paid for an unworked regular holiday', () {
    final r = PayrollCalc.compute(
        one('Daily', 80000, DateTime(2026, 11, 2), hol: {'2026-11-02': 'Regular'}), s);
    expect(r.basic, 0);
    expect(r.holidayPay, 80000);
  });

  test('monthly staff: rest day worked gives +30% of the daily rate', () {
    final r = PayrollCalc.compute(
        one('Monthly', 3100000, DateTime(2026, 10, 10), att: {'2026-10-10': full}), s); // Saturday
    expect(r.basic, 100000);
    expect(r.restDayPremium, 42759);
  });

  test('night differential: 11pm out gives 60 night minutes at 10%', () {
    final r = PayrollCalc.compute(
        one('Daily', 80000, DateTime(2026, 11, 2), att: {
          '2026-11-02': const AttDay(
              workedMin: 180, overtimeMin: 0, lateMin: 0, complete: true, timeInMin: 1200, timeOutMin: 1380)
        }),
        s);
    expect(r.nightDiff, 1000);
  });

  test('paid leave pays daily staff, and a holiday is not an absence', () {
    final leave = PayrollCalc.compute(
        one('Daily', 80000, DateTime(2026, 11, 2), leave: {'2026-11-02'}), s);
    expect(leave.paidLeavePay, 80000);
    final hol = PayrollCalc.compute(
        one('Monthly', 3100000, DateTime(2026, 10, 12), hol: {'2026-10-12': 'Special'}), s);
    expect(hol.absentDays, 0);
  });
}
