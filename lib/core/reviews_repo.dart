import 'audit.dart';
import 'db.dart';
import 'employees_repo.dart';

class ReviewsRepo {
  /// Rating scale 1-5. Change the labels here if the company uses another scale.
  static const ratingLabels = {
    5: 'Outstanding',
    4: 'Exceeds expectations',
    3: 'Meets expectations',
    2: 'Needs improvement',
    1: 'Unsatisfactory',
  };

  static Future<List<DbRow>> list(int empId) => AppDb.db.query(
        'performance_reviews',
        where: 'employee_id = ?',
        whereArgs: [empId],
        orderBy: 'review_date DESC, id DESC',
      );

  static Future<void> add({
    required int empId,
    required String date,
    required int rating,
    String reviewer = '',
    String comments = '',
  }) async {
    final emp = await EmployeesRepo.byId(empId);
    await AppDb.db.insert('performance_reviews', {
      'employee_id': empId,
      'review_date': date,
      'rating': rating,
      'reviewer': reviewer,
      'comments': comments,
      'created_at': DateTime.now().toIso8601String(),
    });
    await Audit.log('REVIEW_ADDED',
        entity: 'employee',
        entityId: (emp?['emp_code'] as String?) ?? '',
        newValue: '$date rating $rating (${ratingLabels[rating]})');
  }

  static Future<void> delete(int id) async {
    final r = await AppDb.db.query('performance_reviews', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) return;
    final emp = await EmployeesRepo.byId(r.first['employee_id'] as int);
    await AppDb.db.delete('performance_reviews', where: 'id = ?', whereArgs: [id]);
    await Audit.log('REVIEW_DELETED',
        entity: 'employee',
        entityId: (emp?['emp_code'] as String?) ?? '',
        oldValue: '${r.first['review_date']} rating ${r.first['rating']}');
  }
}
