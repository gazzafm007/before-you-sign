import 'package:shared_preferences/shared_preferences.dart';

/// Test-build settings. In the public version the API key will live on
/// ARPRA's server, not on the phone.
class AppSettings {
  static const _kKey = 'anthropic_key';
  static const _kModel = 'model';
  static const _kEmail = 'arpra_email';
  static const _kPayLink = 'stripe_link';
  static const _kFee = 'fee_text';
  static const _kTextScale = 'text_scale';
  static const _kServer = 'server_url';
  static const _kServerKey = 'server_key';
  static const _kFull = 'full_report';

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
}
