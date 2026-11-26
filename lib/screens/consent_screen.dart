import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../settings.dart';

/// Asks the buyer's permission before their documents are sent for checking.
/// Required by Apple (App Review Guideline 5.1.2(i)) because the documents go
/// to a third-party AI service. Returns true if the buyer agrees.
Future<bool> ensureAiConsent(BuildContext context) async {
  final s = AppSettings.instance;
  if (s.aiConsent) return true;
  final ok = await Navigator.push<bool>(
    context,
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ConsentScreen()),
  );
  if (ok == true) {
    await s.setConsent(true);
    return true;
  }
  return false;
}

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});
  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _agree = false;

  Widget _point(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: kAccent),
            const SizedBox(width: 14),
            Expanded(child: Text(text)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Before we check')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('How your documents are checked',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _point(Icons.cloud_upload_outlined,
                'The pages you scan or add are sent securely to ARPRA\'s server.'),
            _point(Icons.smart_toy_outlined,
                'ARPRA\'s server sends them to Anthropic, an artificial intelligence (AI) company in the United States, '
                'whose AI model "Claude" reads them and prepares your report. Anthropic does not use them to train its AI.'),
            _point(Icons.person_outline,
                'Your documents may include names, addresses and other personal details, such as yours or the operator\'s.'),
            _point(Icons.delete_outline,
                'Documents from a free check are deleted from ARPRA\'s server after 7 days. The report is kept for 90 days '
                'in case you ask ARPRA to review it.'),
            _point(Icons.info_outline,
                'The report is a first check, not legal advice. It can miss things or misread a page.'),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(AppSettings.privacyUrl), mode: LaunchMode.externalApplication),
                  child: const Text('Privacy policy'),
                ),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(AppSettings.termsUrl), mode: LaunchMode.externalApplication),
                  child: const Text('Terms'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: CheckboxListTile(
                value: _agree,
                onChanged: (v) => setState(() => _agree = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'I agree to my documents being sent to ARPRA and to Anthropic\'s AI to prepare my report.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _agree ? () => Navigator.pop(context, true) : null,
              child: const Text('Agree and check'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            const SizedBox(height: 14),
            const Text(
              'Prefer not to use AI? Call ARPRA on 1300 798 399 to ask about our Prepurchase Advisory service.',
              style: TextStyle(color: Colors.black54, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
