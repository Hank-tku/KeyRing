import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'services/migration_service.dart';
import 'services/password_repository.dart';
import 'utils/theme_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite for desktop platforms
  if (!kIsWeb) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final PasswordRepository repository = PasswordRepository();

  await repository.init();
  await MigrationService(repository: repository).prepareCompatibility();
  runApp(KeyRingApp(repository: repository));
}

class KeyRingApp extends StatefulWidget {
  const KeyRingApp({super.key, required this.repository});

  final PasswordRepository repository;

  @override
  State<KeyRingApp> createState() => _KeyRingAppState();
}

class _KeyRingAppState extends State<KeyRingApp> {
  bool _unlocked = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KeyRing',
      theme: ThemeConfig.appTheme,
      builder: (BuildContext context, Widget? child) {
        return Container(
          decoration: const BoxDecoration(color: ThemeConfig.mainBgColor),
          child: child,
        );
      },
      home: _unlocked
          ? HomeScreen(repository: widget.repository)
          : LoginScreen(onUnlocked: () => setState(() => _unlocked = true)),
      // 定义命名路由表
      routes: {'/home': (context) => HomeScreen(repository: widget.repository)},
    );
  }
}
