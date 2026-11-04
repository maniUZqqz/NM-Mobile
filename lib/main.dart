import 'package:flutter/material.dart';
import 'package:nm_mobile/app/app.dart';
import 'package:nm_mobile/services/background_service.dart';

export 'package:nm_mobile/app/app.dart' show MyApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const MyApp());
}
