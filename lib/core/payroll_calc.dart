import 'dart:math';

/// Pure payroll math (no Flutter, no database) so it can be unit tested.
///
/// Conventions (change here if the company's rules differ):
///  * Rates come from the rate history: each day uses the entry in effect that day.
///  * Daily pay type: paid for each day with a complete attendance record.
///    Late/undertime reduces that day's pay in proportion to the standard day.
///  * Weekly / Monthly / Annual: pay accrues every calendar day
///    (weekly = rate/7, monthly = rate/days in that month, annual = rate/days in year).
///    Absences, late and undertime are then deducted using the daily rate:
///    monthly = rate x 12 / daysFactor, annual = rate / daysFactor,
///    weekly = rate / working days per week.
///  * An absence is a working day (before today) with no attendance record,
///    that is not a holiday and not paid leave.
///  * Overtime = overtime minutes x (daily rate / standard minutes) x multiplier
///    (same percent on holidays and rest days for now).
///  * Holiday worked: extra premium (regular 200% -> +100% of the day, special
///    130% -> +30%). Daily staff are also paid an unworked regular holiday
///    that falls on a working weekday, if that setting is on.
///  * Rest day (not a working weekday) worked: premium (130% -> +30% of the day).
///  * Night differential: night minutes (10pm-6am) x per-minute rate x percent.
///  * Paid leave: Daily staff are paid the day; fixed-salary staff are not absent.
///    Unpaid leave counts as an absence.
class RateEntry {
  final String effectiveDate, payType; // yyyy-MM-dd
  final int rateCentavos;
  const RateEntry(this.effectiveDate, this.payType, this.rateCentavos);
}

class AttDay {
  final int workedMin, overtimeMin, lateMin;
  final bool complete; // has a time out
  final int? timeInMin, timeOutMin; // minutes since midnight
  const AttDay({
    required this.workedMin,
    required this.overtimeMin,
    required this.lateMin,
    required this.complete,
    this.timeInMin,
    this.timeOutMin,
  });
}

class PayrollSettings {
  final int stdMinutes, daysFactor;
  final Set<int> workWeekdays; // 1 = Monday ... 7 = Sunday
  final double otMultiplier;
  final double holRegularPct, holSpecialPct, restDayPct, ndPct;
  final bool holRegularUnworkedPaid;
  const PayrollSettings({
    required this.stdMinutes,
    required this.daysFactor,
    required this.workWeekdays,
    required this.otMultiplier,
    this.holRegularPct = 200,
    this.holSpecialPct = 130,
    this.holRegularUnworkedPaid = true,
    this.restDayPct = 130,
    this.ndPct = 10,
  });
}

class PayrollCalcInput {
  final DateTime from, to, hired, today;
  final DateTime? terminated;
  final List<RateEntry> entries; // sorted by effective date, oldest first
  final Map<String, AttDay> attendance; // key yyyy-MM-dd
  final Map<String, String> holidays; // key -> 'Regular' | 'Special'
  final Set<String> paidLeave; // keys of paid leave days
  const PayrollCalcInput({
    required this.from,
    required this.to,
    required this.hired,
    required this.today,
    this.terminated,
    required this.entries,
    required this.attendance,
    this.holidays = const {},
    this.paidLeave = const {},
  });
}

class PayrollCalcResult {
  final int basic, overtime, absenceDed, lateDed;
  final int holidayPay, holidayPremium, restDayPremium, nightDiff, paidLeavePay;
  final int daysWorked, absentDays, paidLeaveDays, shortfallMin, overtimeMin;
  final List<String> warnings;
  const PayrollCalcResult({
    required this.basic,
    required this.overtime,
    required this.absenceDed,
    required this.lateDed,
    this.holidayPay = 0,
    this.holidayPremium = 0,
    this.restDayPremium = 0,
    this.nightDiff = 0,
    this.paidLeavePay = 0,
    required this.daysWorked,
    required this.absentDays,
    this.paidLeaveDays = 0,
    required this.shortfallMin,
    required this.overtimeMin,
    required this.warnings,
  });
}

class PayrollCalc {
  static String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static RateEntry? entryOn(List<RateEntry> sorted, String k) {
    RateEntry? r;
    for (final e in sorted) {
      if (e.effectiveDate.compareTo(k) <= 0) {
        r = e;
      } else {
        break;
      }
    }
    return r;
  }

  static double dailyRate(String type, int r, PayrollSettings s) {
    switch (type) {
      case 'Weekly':
        return r / (s.workWeekdays.isEmpty ? 5 : s.workWeekdays.length);
      case 'Monthly':
        return r * 12 / s.daysFactor;
      case 'Annual':
        return r / s.daysFactor;
      default:
        return r.toDouble();
    }
  }

  static bool _leap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

  static double accrual(String type, int r, DateTime d) {
    switch (type) {
      case 'Weekly':
        return r / 7;
      case 'Monthly':
        return r / DateTime(d.year, d.month + 1, 0).day;
      case 'Annual':
        return r / (_leap(d.year) ? 366 : 365);
      default:
        return 0;
    }
  }

  static int _overlap(int a1, int a2, int b1, int b2) {
    final s = max(a1, b1), e = min(a2, b2);
    return e > s ? e - s : 0;
  }

  /// Minutes between 10pm and 6am inside [timeIn, timeOut] (same-day shifts).
  static int nightMinutes(int timeIn, int timeOut) =>
      _overlap(timeIn, timeOut, 0, 360) + _overlap(timeIn, timeOut, 1320, 1440);

  static PayrollCalcResult compute(PayrollCalcInput i, PayrollSettings s) {
    double basic = 0, ot = 0, absDed = 0, lateDed = 0;
    double holPay = 0, holPrem = 0, restPrem = 0, night = 0, leavePay = 0;
    int days = 0, absent = 0, leaveDays = 0, shortMin = 0, otMin = 0;
    final warnings = <String>[];

    final start = i.hired.isAfter(i.from) ? i.hired : i.from;
    final end = (i.terminated != null && i.terminated!.isBefore(i.to))
        ? i.terminated!
        : i.to;

    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
      final k = key(d);
      final e = entryOn(i.entries, k);
      if (e == null) continue;
      final att = i.attendance[k];
      final daily = dailyRate(e.payType, e.rateCentavos, s);
      final perMin = daily / s.stdMinutes;
      final isWorkDay = s.workWeekdays.contains(d.weekday);
      final isDailyType = e.payType == 'Daily';
      final hol = i.holidays[k]; // null when not a holiday
      final onLeave = i.paidLeave.contains(k);

      if (!isDailyType) basic += accrual(e.payType, e.rateCentavos, d);

      if (att == null) {
        if (isDailyType) {
          if (onLeave) {
            leavePay += daily;
            leaveDays++;
          } else if (hol == 'Regular' && s.holRegularUnworkedPaid && isWorkDay) {
            holPay += daily;
          }
        } else {
          if (onLeave) leaveDays++;
          if (isWorkDay && d.isBefore(i.today) && hol == null && !onLeave) {
            absent++;
            absDed += daily;
          }
        }
        continue;
      }
      if (!att.complete) {
        warnings.add('$k: no time out recorded');
        if (!isDailyType) lateDed += perMin * att.lateMin;
        continue;
      }
      final regular = min(max(att.workedMin - att.overtimeMin, 0), s.stdMinutes);
      days++;
      otMin += att.overtimeMin;
      ot += att.overtimeMin * perMin * s.otMultiplier;
      if (isDailyType) {
        basic += daily * regular / s.stdMinutes;
      } else if (isWorkDay) {
        final short = s.stdMinutes - regular;
        if (short > 0) {
          shortMin += short;
          lateDed += perMin * short;
        }
      }
      // premiums for working on a holiday or a rest day
      double pct = 0;
      if (hol == 'Regular') {
        pct = s.holRegularPct - 100;
      } else if (hol == 'Special') {
        pct = s.holSpecialPct - 100;
      } else if (!isWorkDay) {
        pct = s.restDayPct - 100;
      }
      if (pct > 0) {
        final amt = daily * regular / s.stdMinutes * pct / 100;
        if (hol != null) {
          holPrem += amt;
        } else {
          restPrem += amt;
        }
      }
      // night differential
      if (att.timeInMin != null && att.timeOutMin != null && att.timeOutMin! > att.timeInMin!) {
        final nm = nightMinutes(att.timeInMin!, att.timeOutMin!);
        night += nm * perMin * s.ndPct / 100;
      }
    }

    return PayrollCalcResult(
      basic: basic.round(),
      overtime: ot.round(),
      absenceDed: absDed.round(),
      lateDed: lateDed.round(),
      holidayPay: holPay.round(),
      holidayPremium: holPrem.round(),
      restDayPremium: restPrem.round(),
      nightDiff: night.round(),
      paidLeavePay: leavePay.round(),
      daysWorked: days,
      absentDays: absent,
      paidLeaveDays: leaveDays,
      shortfallMin: shortMin,
      overtimeMin: otMin,
      warnings: warnings,
    );
  }
}
