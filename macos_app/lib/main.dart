import 'cy_localization.dart';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'app_commands.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppCommandDispatcher.initialize();
  await CyLanguage.instance.load();
  runApp(const PersonalPdfApp());
}
