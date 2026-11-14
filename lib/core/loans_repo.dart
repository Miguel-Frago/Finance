import 'audit.dart';
import 'db.dart';
import 'employees_repo.dart';

/// Loans and cash advances. A payroll deducts min(amount per payroll, balance)
/// automatically. The balance only goes down when the payroll is approved,
/// and goes back up if that payroll is reopened.
/// NOTE: loan rules (limits, interest) must be updated to the company's rules.
class LoansRepo {
  static Future<List<DbRow>> list({String status = 'All'}) => AppDb.db.rawQuery('''
    SELECT l.*, e.last_name, e.first_name, e.emp_code,
      (SELECT COALESCE(SUM(amount_centavos), 0) FROM loan_payments p WHERE p.loan_id = l.id) AS paid
    FROM loans l JOIN employees e ON e.id = l.employee_id
    ${status == 'All' ? '' : "WHERE l.status = '$status'"}
    ORDER BY (l.status = 'Active') DESC, l.id DESC''');

  static Future<List<DbRow>> payments(int loanId) => AppDb.db.query('loan_payments',
      where: 'loan_id = ?', whereArgs: [loanId], orderBy: 'id DESC');

  static Future<void> add({
    required int empId,
    required String label,
    required int principal,
    required int perPayroll,
    required String startDate,
    String note = '',
  }) async {
    final emp = await EmployeesRepo.byId(empId);
    await AppDb.db.insert('loans', {
      'employee_id': empId,
      'label': label,
      'principal_centavos': principal,
      'per_payroll_centavos': perPayroll,
      'balance_centavos': principal,
      'status': 'Active',
      'start_date': startDate,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    });
    await Audit.log('LOAN_ADDED',
        entity: 'loan',
        entityId: '${emp?['emp_code']}',
        newValue:
            '$label ${EmployeesRepo.pesos(principal)}, ${EmployeesRepo.pesos(perPayroll)} per payroll');
  }

  static Future<void> setPerPayroll(int id, int centavos) async {
    final r = await AppDb.db.query('loans', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) return;
    await AppDb.db.update('loans', {'per_payroll_centavos': centavos},
        where: 'id = ?', whereArgs: [id]);
    await Audit.log('LOAN_UPDATED',
        entity: 'loan',
        entityId: '${r.first['label']}',
        oldValue: 'per payroll ${EmployeesRepo.pesos(r.first['per_payroll_centavos'] as int)}',
        newValue: 'per payroll ${EmployeesRepo.pesos(centavos)}');
  }

  /// Stops deductions. History and the remaining balance are kept.
  static Future<void> cancel(int id) async {
    final r = await AppDb.db.query('loans', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) return;
    await AppDb.db.update('loans', {'status': 'Cancelled'}, where: 'id = ?', whereArgs: [id]);
    await Audit.log('LOAN_CANCELLED',
        entity: 'loan',
        entityId: '${r.first['label']}',
        oldValue: 'balance ${EmployeesRepo.pesos(r.first['balance_centavos'] as int)}');
  }
}
