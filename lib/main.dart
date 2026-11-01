import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'settings.dart';

const kAccent = Color(0xFF2326C9);
const kRed = Color(0xFFB3261E);
const kAmber = Color(0xFF8A5300);
const kGreen = Color(0xFF1E6B3A);
const kRedBg = Color(0xFFFCEBEA);
const kAmberBg = Color(0xFFFFF4DE);
const kGreenBg = Color(0xFFE6F4EA);

final ValueNotifier<double> textScale = ValueNotifier(1.0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  textScale.value = AppSettings.instance.textScale;
  runApp(const BeforeYouSignApp());
}

class BeforeYouSignApp extends StatelessWidget {
  const BeforeYouSignApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: kAccent, primary: kAccent, brightness: Brightness.light);
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: 'Atkinson',
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
    );
    final theme = base.copyWith(
      textTheme: base.textTheme.copyWith(
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 18, height: 1.4),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 16.5, height: 1.4),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Atkinson'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, fontFamily: 'Atkinson'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFDADCE3)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    );

    return ValueListenableBuilder<double>(
      valueListenable: textScale,
      builder: (context, scale, _) => MaterialApp(
        title: 'Before You Sign',
        debugShowCheckedModeBanner: false,
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
