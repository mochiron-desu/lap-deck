import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/deck_theme.dart';
import 'services/app_logger.dart';
import 'services/storage_service.dart';
import 'services/ssh_service.dart';
import 'services/terminal_session_controller.dart';
import 'ui/screens/app_scaffold.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppLogger.init();
  AppLogger.info('App', 'LAPDECK v1.2.0 starting up...');

  // Catch Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLogger.error(
      'FlutterError',
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
  };

  // Catch unhandled async / platform errors
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.error('PlatformDispatcher', error.toString(), error, stack);
    return true;
  };

  // Set system UI overlay style to deep dark tactical styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: DeckColors.surfaceCore,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final storage = await StorageService.init();
  final sshService = SshService();
  final terminalController = TerminalSessionController(sshService);

  runApp(LapDeckApp(
    storage: storage,
    sshService: sshService,
    terminalController: terminalController,
  ));
}

class LapDeckApp extends StatelessWidget {
  final StorageService storage;
  final SshService sshService;
  final TerminalSessionController terminalController;

  const LapDeckApp({
    super.key,
    required this.storage,
    required this.sshService,
    required this.terminalController,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LapDeck',
      debugShowCheckedModeBanner: false,
      theme: DeckTheme.darkTheme,
      home: AppScaffold(
        storage: storage,
        sshService: sshService,
        terminalController: terminalController,
      ),
    );
  }
}
