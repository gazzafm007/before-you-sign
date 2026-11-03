import 'package:flutter/material.dart';

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
      appBar: AppBar(title: const Text('Settings')),
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
          const SizedBox(height: 24),
          const Text('Before You Sign · test build 0.5 · ARPRA Limited',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 14)),
        ],
      ),
    );
  }
}
