import 'package:flutter/material.dart';
import 'core/db.dart';
import 'core/rates_repo.dart';
import 'core/settings.dart';
import 'theme/app_theme.dart';
import 'ui/home_shell.dart';
import 'ui/lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDb.init();
  await Settings.load();
  await RatesRepo.syncAll();
  themeId.value = Settings.get('theme', 'light');
  runApp(const BfmApp());
}

class BfmApp extends StatelessWidget {
  const BfmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: themeId,
      builder: (context, id, _) => MaterialApp(
        title: 'Business Financial Monitoring',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(id),
        builder: (context, child) => LockGate(child: child!),
        home: const HomeShell(),
      ),
    );
  }
}
