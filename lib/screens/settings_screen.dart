import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final s = AppSettings.instance;
  late final _key = TextEditingController(text: s.apiKey);
  late final _email = TextEditingController(text: s.arpraEmail);
  late final _link = TextEditingController(text: s.paymentLink);
  late final _fee = TextEditingController(text: s.feeText);
  late final _server = TextEditingController(text: s.serverUrl);
  late final _serverKey = TextEditingController(text: s.serverKey);
  late String _model = s.model;
  late double _scale = s.textScale;
  late bool _full = s.fullReport;
  bool _show = false;

  @override
  void dispose() {
    _key.dispose();
    _email.dispose();
    _link.dispose();
    _fee.dispose();
    _server.dispose();
    _serverKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!AppSettings.testBuild) {
      await s.saveTextScale(_scale);
      textScale.value = _scale;
      if (mounted) Navigator.pop(context);
      return;
    }
    s.apiKey = _key.text.trim();
    s.arpraEmail = _email.text.trim().isEmpty ? 'prepurchase@arpra.org.au' : _email.text.trim();
    s.paymentLink = _link.text.trim();
    s.feeText = _fee.text.trim();
    s.serverUrl = _server.text.trim();
    s.serverKey = _serverKey.text.trim();
    s.model = _model;
    s.textScale = _scale;
    s.fullReport = _full;
    await s.save();
    textScale.value = _scale;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings and help')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Text size', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _scale,
            min: .9,
            max: 1.5,
            divisions: 6,
            label: '${(_scale * 100).round()}%',
            onChanged: (v) => setState(() => _scale = v),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('Save text size')),
          const Divider(height: 32),
          Text('Help and policies', style: Theme.of(context).textTheme.titleMedium),
          _linkTile(Icons.call_outlined, 'Call ARPRA on 1300 798 399', 'tel:1300798399'),
          _linkTile(Icons.mail_outline, 'Email prepurchase@arpra.org.au', 'mailto:prepurchase@arpra.org.au'),
          _linkTile(Icons.privacy_tip_outlined, 'Privacy policy', AppSettings.privacyUrl),
          _linkTile(Icons.description_outlined, 'Terms and disclaimer', AppSettings.termsUrl),
          _linkTile(Icons.currency_exchange, 'Refunds and cancellations', AppSettings.refundsUrl),
          if (s.aiConsent)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.undo),
              title: const Text('Withdraw my agreement to send documents for checking'),
              subtitle: const Text('You will be asked again before your next check.'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                await s.setConsent(false);
                if (!mounted) return;
                setState(() {});
                messenger.showSnackBar(const SnackBar(content: Text('Done. We will ask again before your next check.')));
              },
            ),
          if (AppSettings.testBuild) ...[
          const Divider(height: 32),
          Text('Test build settings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            'These are for ARPRA testing only. In the public version the checking key sits on ARPRA\'s server, '
            'not on the phone.',
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _key,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Claude API key',
              helperText: 'From console.anthropic.com → API keys. Stored only on this phone.',
              suffixIcon: IconButton(
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _model,
            decoration: const InputDecoration(labelText: 'Checking model'),
            items: AppSettings.models.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _model = v ?? AppSettings.defaultModel),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'ARPRA review requests go to'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Stripe Payment Link (optional)',
              helperText: 'e.g. https://buy.stripe.com/test_… Leave blank to skip payment.',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _fee,
            decoration: const InputDecoration(
              labelText: 'Fee shown to buyers',
              helperText: 'e.g. \$165 including GST',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _server,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'ARPRA server (optional)',
              helperText: 'e.g. https://www.arpra.org.au/bys — confirms payment with Stripe and receives the documents.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _serverKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Server key',
              helperText: 'The app_key from config.php on the server.',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _full,
            onChanged: (v) => setState(() => _full = v),
            title: const Text('Show the full report to everyone'),
            subtitle: const Text('For ARPRA testing. Turn off to see what the public will see: a free summary, '
                'with the full report after paying for ARPRA\'s review.'),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save')),
          ],
          const SizedBox(height: 24),
          Text('Clear to Sign by ARPRA · version $kAppVersion${AppSettings.testBuild ? ' (test build)' : ''}\nARPRA Limited · PO Box 4063, Forster NSW 2428',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _linkTile(IconData icon, String label, String url) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(label),
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      );
}
