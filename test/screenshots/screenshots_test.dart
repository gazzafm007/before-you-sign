// Renders store screenshots of Clear to Sign (not a real test).
// Run: flutter test test/screenshots/screenshots_test.dart --update-goldens
import 'dart:io';

import 'package:before_you_sign/main.dart';
import 'package:before_you_sign/models.dart';
import 'package:before_you_sign/sample.dart';
import 'package:before_you_sign/screens/consent_screen.dart';
import 'package:before_you_sign/screens/home_screen.dart';
import 'package:before_you_sign/screens/report_screen.dart';
import 'package:before_you_sign/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePaths extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  final String dir;
  _FakePaths(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

Future<void> _font(String family, String path) async {
  final l = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await l.load();
}

void main() {
  final shots = {
    'phone': const Size(1080, 2340), // Google Play phone
    'iphone69': const Size(1320, 2868), // App Store 6.9-inch
    'ipad13': const Size(2064, 2752), // App Store 13-inch iPad
    'iphone63': const Size(1206, 2622), // App Store iPhone with Dynamic Island (medium)
  };
  const dpr = 3.0;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _font('Atkinson', 'assets/fonts/AtkinsonHyperlegible-Regular.ttf');
    await _font('Atkinson', 'assets/fonts/AtkinsonHyperlegible-Bold.ttf');
    await _font('MaterialIcons', '/opt/fl/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    await _font('Roboto', '/opt/fl/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
    final tmp = Directory.systemTemp.createTempSync('cts');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    SharedPreferences.setMockInitialValues({'ai_consent_v1': true});
    await AppSettings.instance.load();
  });

  CheckCase sampleCase() => CheckCase.create()
    ..sample = true
    ..community = 'Riverbend Lakes Village (example)'
    ..site = '58'
    ..buyer = 'Pat Example'
    ..report = Map<String, dynamic>.from(kSampleReport)
    ..checkedAt = DateTime(2026, 11, 20)
    ..model = 'sample';

  for (final e in shots.entries) {
    Future<void> shot(WidgetTester t, Widget w, String name, {String? scrollTo}) async {
      t.view.physicalSize = e.value;
      t.view.devicePixelRatio = dpr;
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() async {
        await t.pumpWidget(_wrap(w));
        await Future.delayed(const Duration(milliseconds: 600));
      });
      for (var i = 0; i < 6; i++) {
        await t.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.runAsync(() async {
        for (final el in find.byType(Image).evaluate()) {
          final img = el.widget as Image;
          await precacheImage(img.image, el);
        }
      });
      await t.pump(const Duration(seconds: 1));
      if (scrollTo != null) {
        await t.scrollUntilVisible(find.textContaining(scrollTo), 200, scrollable: find.byType(Scrollable).first);
        await t.ensureVisible(find.textContaining(scrollTo));
        await t.pump(const Duration(seconds: 1));
        await t.drag(find.byType(Scrollable).first, const Offset(0, 120));
        await t.pump(const Duration(seconds: 1));
      }
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/${e.key}_$name.png'));
    }

    testWidgets('${e.key} home', (t) async {
      await t.runAsync(() => CaseStore.save(sampleCase()));
      await shot(t, const HomeScreen(), '1_home');
    });
    testWidgets('${e.key} report', (t) async {
      await shot(t, ReportScreen(checkCase: sampleCase()), '2_report');
    });
    testWidgets('${e.key} report more', (t) async {
      await shot(t, ReportScreen(checkCase: sampleCase()), '3_report_more', scrollTo: 'Look closely before you sign');
    });
    testWidgets('${e.key} consent', (t) async {
      await shot(t, const ConsentScreen(), '4_consent');
    });
  }
}

Widget _wrap(Widget home) => _ShotApp(home: home);

class _ShotApp extends StatelessWidget {
  final Widget home;
  const _ShotApp({required this.home});
  @override
  Widget build(BuildContext context) {
    // Reuse the app's theme by building the real app and swapping the home.
    final app = const ClearToSignApp().build(context) as ValueListenableBuilder<double>;
    return ValueListenableBuilder<double>(
      valueListenable: app.valueListenable,
      builder: (c, v, child) {
        final m = app.builder(c, v, child) as MaterialApp;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: m.theme,
          builder: m.builder,
          home: home,
        );
      },
    );
  }
}
