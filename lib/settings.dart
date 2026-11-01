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

  static const defaultModel = 'claude-opus-5-5';
  static const models = {
    'claude-opus-5-5': 'Claude Opus (most thorough)',
    'claude-sonnet-5-5': 'Claude Sonnet (faster, cheaper)',
  };

  String apiKey = '';
  String model = defaultModel;
  String arpraEmail = 'gary.martin@arpra.org.au';
  String paymentLink = '';
  String feeText = '';
  double textScale = 1.0;

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
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kKey, apiKey.trim());
    await p.setString(_kModel, model);
    await p.setString(_kEmail, arpraEmail.trim());
    await p.setString(_kPayLink, paymentLink.trim());
    await p.setString(_kFee, feeText.trim());
    await p.setDouble(_kTextScale, textScale);
  }

  bool get hasKey => apiKey.trim().isNotEmpty;
}
