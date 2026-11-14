import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'attendance_screen.dart';
import 'audit_screen.dart';
import 'dashboard_screen.dart';
import 'employees_screen.dart';
import 'holidays_leave_screen.dart';
import 'loans_screen.dart';
import 'payroll_screen.dart';
import 'placeholder_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

class _Dest {
  final String label;
  final IconData icon;
  final Widget screen;
  final String? tag; // e.g. "Soon", "Phase 2"
  const _Dest(this.label, this.icon, this.screen, {this.tag});
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;

  late final List<_Dest> _dests = [
    const _Dest('Dashboard', Icons.dashboard_rounded, DashboardScreen()),
    const _Dest('Employees', Icons.people_alt_rounded, EmployeesScreen()),
    const _Dest('Attendance', Icons.access_time_rounded, AttendanceScreen()),
    const _Dest('Payroll', Icons.payments_rounded, PayrollScreen()),
    const _Dest('Holidays & Leave', Icons.event_available_rounded, HolidaysLeaveScreen()),
    const _Dest('Loans', Icons.request_quote_rounded, LoansScreen()),
    const _Dest('Reports', Icons.print_rounded, ReportsScreen()),
    const _Dest('Renting', Icons.home_work_rounded,
        PlaceholderScreen('Renting', Icons.home_work_rounded,
            'Properties, tenants, contracts and rent payments will be added once the business rules are defined.',
            status: Status.inactive, tag: 'Coming Soon'),
        tag: 'Soon'),
    const _Dest('Financial Overview', Icons.insights_rounded,
        PlaceholderScreen('Financial Overview', Icons.insights_rounded,
            'Payroll expenses vs. rental income in one view. Coming after the renting module.',
            status: Status.inactive, tag: 'Coming Soon'),
        tag: 'Soon'),
    const _Dest('Audit Trail', Icons.fact_check_rounded, AuditScreen()),
    const _Dest('Settings', Icons.settings_rounded, SettingsScreen()),
  ];

  Widget _sidebar({bool inDrawer = false}) {
    return SizedBox(
      width: 250,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 30),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ZENTRIX',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.2,
                          )),
                      SizedBox(height: 3),
                      Text('BUSINESS MANAGEMENT SYSTEM',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.05,
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          for (var n = 0; n < _dests.length; n++)
            ListTile(
              selected: n == _i,
              leading: Icon(_dests[n].icon),
              title: Text(_dests[n].label),
              trailing: _dests[n].tag == null
                  ? null
                  : Text(_dests[n].tag!,
                      style: Theme.of(context).textTheme.labelSmall),
              onTap: () {
                setState(() => _i = n);
                if (inDrawer) Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }

  void _more() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (var n = 4; n < _dests.length; n++)
            ListTile(
              selected: n == _i,
              leading: Icon(_dests[n].icon),
              title: Text(_dests[n].label),
              trailing: _dests[n].tag == null ? null : Text(_dests[n].tag!),
              onTap: () {
                Navigator.pop(c);
                setState(() => _i = n);
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final body = KeyedSubtree(key: ValueKey(_i), child: _dests[_i].screen);
    if (wide) {
      return Scaffold(
        body: Row(children: [
          _sidebar(),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    // Phone and tablet: bottom bar with the four main screens and "More".
    return Scaffold(
      appBar: AppBar(title: Text(_dests[_i].label)),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i < 4 ? _i : 4,
        onDestinationSelected: (n) {
          if (n == 4) {
            _more();
          } else {
            setState(() => _i = n);
          }
        },
        destinations: [
          for (var n = 0; n < 4; n++)
            NavigationDestination(icon: Icon(_dests[n].icon), label: _dests[n].label),
          const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
