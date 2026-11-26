import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// App settings.
///
/// Store builds: the ARPRA server and its key are built in
/// (--dart-define=CTS_SERVER_KEY=… from Codemagic), and the payment link and
/// fee come from the server, so nothing can be changed on the phone.
/// Test builds (--dart-define=CTS_TEST=true) also show ARPRA's test settings.
class AppSettings {
  static const bool testBuild = bool.fromEnvironment('CTS_TEST');

  /// ARPRA's server. apps.arpra.org.au is ARPRA's own address for it, so the
  /// server can move host (GoDaddy → Azure) by changing DNS, not the app.
  static const String builtInServer =
      String.fromEnvironment('CTS_SERVER', defaultValue: 'https://apps.arpra.org.au/bys');
  static const String builtInServerKey = String.fromEnvironment('CTS_SERVER_KEY');

  static const appName = 'Clear to Sign';
  static const privacyUrl = 'https://www.arpra.org.au/privacy.html';
  static const termsUrl = 'https://www.arpra.org.au/terms.html';
  static const refundsUrl = 'https://www.arpra.org.au/refunds.html';

  static const _kKey = 'anthropic_key';
  static const _kModel = 'model';
  static const _kEmail = 'arpra_email';
  static const _kPayLink = 'stripe_link';
  static const _kFee = 'fee_text';
  static const _kTextScale = 'text_scale';
  static const _kServer = 'server_url';
  static const _kServerKey = 'server_key';
  static const _kFull = 'full_report';
  static const _kDevice = 'device_id';
  static const _kConsent = 'ai_consent_v1';

  static const defaultModel = 'claude-opus-5-5';
  static const models = {
    'claude-opus-5-5': 'Claude Opus (most thorough)',
    'claude-sonnet-5-5': 'Claude Sonnet (faster, cheaper)',
  };

  String apiKey = '';
  String model = defaultModel;
  String arpraEmail = 'prepurchase@arpra.org.au';
  String paymentLink = '';
  String feeText = '';
  double textScale = 1.0;

  /// ARPRA's Before You Sign server folder, e.g. https://www.arpra.org.au/bys
  /// When set, payment is confirmed by the server (Stripe webhook) and the
  /// documents are uploaded there instead of emailed from the phone.
  String serverUrl = '';
  String serverKey = '';

  /// Test build: show every buyer the full report. Off = the public
  /// behaviour (free summary; full report after paying for ARPRA's review).
  bool fullReport = true;

  /// The buyer agreed to their documents going to ARPRA and Anthropic.
  bool aiConsent = false;

  /// Random id for this install, so ARPRA's server can apply daily limits.
  String deviceId = '';

  static final AppSettings instance = AppSettings();

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    apiKey = p.getString(_kKey) ?? '';
    model = p.getString(_kModel) ?? defaultModel;
    if (!models.containsKey(model)) model = defaultModel;
    arpraEmail = p.getString(_kEmail) ?? arpraEmail;
    paymentLink = p.getString(_kPayLink) ?? '';
    feeText = p.getString(_kFee) ?? '';
    textScale = p.getDouble(_kTextScale) ?? 1.0;
    serverUrl = p.getString(_kServer) ?? '';
    serverKey = p.getString(_kServerKey) ?? '';
    fullReport = p.getBool(_kFull) ?? true;
    aiConsent = p.getBool(_kConsent) ?? false;
    if (!testBuild) {
      // Store build: fixed server; the server decides summary or full report.
      apiKey = '';
      model = defaultModel;
      serverUrl = builtInServer;
      serverKey = builtInServerKey;
      fullReport = true;
      paymentLink = '';
      feeText = '';
    } else if (serverUrl.isEmpty && builtInServerKey.isNotEmpty) {
      serverUrl = builtInServer;
      serverKey = builtInServerKey;
    }
    deviceId = p.getString(_kDevice) ?? '';
    if (deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await p.setString(_kDevice, deviceId);
    }
  }

  Future<void> setConsent(bool v) async {
    aiConsent = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kConsent, v);
  }

  Future<void> saveTextScale(double v) async {
    textScale = v;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kTextScale, v);
  }

  /// Store build: fetch the payment link and fee from ARPRA's server.
  Future<void> loadServerConfig() async {
    if (testBuild && paymentLink.isNotEmpty) return;
    if (serverUrl.isEmpty) return;
    try {
      final r = await http
          .get(serverUri('web-config.php'), headers: {'X-BYS-Key': serverKey, 'X-BYS-Device': deviceId})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final link = (j['payment_link'] ?? '').toString();
      if (link.isNotEmpty) paymentLink = link;
      final fee = (j['fee_text'] ?? '').toString();
      if (fee.isNotEmpty) feeText = fee;
    } catch (_) {
      // Tried again when the buyer opens the review screen.
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kKey, apiKey.trim());
    await p.setString(_kModel, model);
    await p.setString(_kEmail, arpraEmail.trim());
    await p.setString(_kPayLink, paymentLink.trim());
    await p.setString(_kFee, feeText.trim());
    await p.setDouble(_kTextScale, textScale);
    await p.setString(_kServer, serverUrl.trim());
    await p.setString(_kServerKey, serverKey.trim());
    await p.setBool(_kFull, fullReport);
  }

  bool get hasServer => serverUrl.trim().isNotEmpty && serverKey.trim().isNotEmpty;

  /// Builds the address of one of the server scripts, e.g. check.php.
  Uri serverUri(String script, [Map<String, String>? query]) {
    var base = serverUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Uri.parse('$base/$script').replace(queryParameters: query);
  }

  bool get hasKey => apiKey.trim().isNotEmpty;

  /// Checks run on ARPRA's server when it is set; otherwise (testing) on the
  /// phone with the key from Settings.
  bool get canCheck => hasServer || hasKey;
}
