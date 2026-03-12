// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Analytics Dashboard';

  @override
  String get startServer => 'START SERVER';

  @override
  String get stopServer => 'STOP SERVER';

  @override
  String get expectedIp => 'Expected PC IP Address';
}
