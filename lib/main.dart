import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/deck_theme.dart';
import 'services/storage_service.dart';
import 'services/ssh_service.dart';
import 'ui/screens/deck_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(LapDeckApp(
    storage: storage,
    sshService: sshService,
  ));
}

class LapDeckApp extends StatelessWidget {
  final StorageService storage;
  final SshService sshService;

  const LapDeckApp({
    super.key,
    required this.storage,
    required this.sshService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LapDeck',
      debugShowCheckedModeBanner: false,
      theme: DeckTheme.darkTheme,
      home: DeckScreen(
        storage: storage,
        sshService: sshService,
      ),
    );
  }
}
