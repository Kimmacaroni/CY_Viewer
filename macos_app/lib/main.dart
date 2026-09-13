import 'package:flutter/widgets.dart';

import 'app.dart';
import 'app_commands.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppCommandDispatcher.initialize();
  runApp(const PersonalPdfApp());
}
