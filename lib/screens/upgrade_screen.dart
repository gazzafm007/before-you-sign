import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../models.dart';
import '../report_pdf.dart';
import '../settings.dart';

/// The paid upgrade: pay ARPRA's pre-purchase advice fee (Stripe Payment
/// Link) and send the documents and report to ARPRA.
///
/// With an ARPRA server set in Settings, payment is confirmed by the server
/// (Stripe tells it directly through a webhook) and the documents are
/// uploaded there. Without one, the test-build fallback asks the buyer and
/// sends the documents by email from the phone.
class UpgradeScreen extends StatefulWidget {
  final CheckCase checkCase;
  const UpgradeScreen({super.key, required this.checkCase});
  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> with WidgetsBindingObserver {
  CheckCase get c => widget.checkCase;
  late final _name = TextEditingController(text: c.buyer);
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _when = TextEditingController();
  bool _consent = false;
  bool _paid = false;
  bool _sending = false;
  bool _sent = false;

  // Server payment confirmation.
  bool _waiting = false; // payment page opened, waiting for Stripe
  bool _checking = false;
  bool _testPayment = false;
  Timer? _poll;
  int _polls = 0;

  AppSettings get _s => AppSettings.instance;
  bool get _useServer => _s.hasServer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The buyer may have paid earlier and come back to this screen.
    if (_useServer) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkPaid(quiet: true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the Stripe page in the browser.
    if (state == AppLifecycleState.resumed && _waiting && !_paid) _checkPaid(quiet: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _when.dispose();
    super.dispose();
  }

  bool get _detailsOk =>
      _name.text.trim().isNotEmpty && (_email.text.contains('@') || _phone.text.trim().length >= 8) && _consent;

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pay() async {
    final link = AppSettings.instance.paymentLink;
    if (link.isEmpty) {
      setState(() => _paid = true);
      _snack('Test build: no Stripe payment link set in Settings, so payment is skipped.');
      return;
    }
    final uri = Uri.parse(link).replace(queryParameters: {
      ...Uri.parse(link).queryParameters,
      'client_reference_id': c.reference,
      if (_email.text.contains('@')) 'prefilled_email': _email.text.trim(),
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      _snack('Could not open the payment page.');
      return;
    }
    if (!mounted) return;
    if (_useServer) {
      _startPolling();
      return;
    }
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment'),
        content: const Text('Did the payment go through?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, paid')),
        ],
      ),
    );
    if (done == true) {
      c.fullUnlocked = true;
      await CaseStore.save(c);
      setState(() => _paid = true);
    }
  }

  /// Checks with ARPRA's server every few seconds for up to 15 minutes.
  void _startPolling() {
    _poll?.cancel();
    _polls = 0;
    setState(() => _waiting = true);
    _poll = Timer.periodic(const Duration(seconds: 4), (t) {
      _polls++;
      if (_paid || _polls > 225 || !mounted) {
        t.cancel();
        return;
      }
      _checkPaid(quiet: true);
    });
  }

  /// Asks the server whether Stripe has confirmed payment for this case.
  Future<void> _checkPaid({bool quiet = false}) async {
    if (_checking || !_useServer) return;
    setState(() => _checking = true);
    try {
      final resp = await http
          .get(_s.serverUri('check.php', {'ref': c.reference}), headers: {'X-BYS-Key': _s.serverKey})
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 403) {
        if (!quiet) {
          _snack(resp.body.contains('Website Security')
              ? 'ARPRA\'s website firewall blocked the payment check (error 403).'
              : 'The server key in Settings was not accepted.');
        }
        return;
      }
      if (resp.statusCode != 200) {
        if (!quiet) _snack('Could not check the payment (error ${resp.statusCode}). Please try again.');
        return;
      }
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (j['paid'] == true) {
        _poll?.cancel();
        if (!c.fullUnlocked) {
          c.fullUnlocked = true;
          await CaseStore.save(c);
        }
        setState(() {
          _paid = true;
          _waiting = false;
          _testPayment = j['test'] == true;
          _sent = j['emailed'] == true;
        });
      } else if (!quiet) {
        _snack('No payment has been confirmed yet. If you have just paid, wait a moment and try again.');
      }
    } catch (_) {
      if (!quiet && mounted) _snack('Could not reach ARPRA to check the payment. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// Uploads everything to ARPRA's server, which emails it to ARPRA once
  /// payment is confirmed. Returns true when it has been sent to ARPRA.
  Future<bool> _upload(List<String> files, Map<String, dynamic> meta) async {
    final req = http.MultipartRequest('POST', _s.serverUri('request.php'))
      ..headers['X-BYS-Key'] = _s.serverKey
      ..fields['ref'] = c.reference
      ..fields['meta'] = jsonEncode(meta);
    for (final p in files) {
      req.files.add(await http.MultipartFile.fromPath('files[]', p));
    }
    final streamed = await req.send().timeout(const Duration(minutes: 6));
    final resp = await http.Response.fromStream(streamed);
    Map<String, dynamic> j = {};
    try {
      j = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {}
    if (resp.statusCode == 413) {
      throw Exception('The documents are too large to send in one go. Remove duplicate pages or use PDFs instead of photos.');
    }
    if (resp.statusCode != 200 || j['ok'] != true) {
      if (j['error'] == 'Not allowed.') {
        throw Exception('the server key in Settings does not match the server (error 403).');
      }
      if (resp.body.contains('Website Security')) {
        throw Exception('ARPRA\'s website firewall blocked the upload (error ${resp.statusCode}). '
            'The /bys/ folder needs to be allowed in GoDaddy Website Security.');
      }
      throw Exception(j['error'] ?? 'The server replied with error ${resp.statusCode}.');
    }
    return j['emailed'] == true;
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/arpra_${c.id}');
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);

      final attachments = <String>[];
      if (c.report != null) attachments.add((await buildReportPdf(c, dir, full: true)).path);
      for (final d in c.docs) {
        final scanned = await pagesToPdf(d, dir, c.reference);
        if (scanned != null) attachments.add(scanned.path);
        for (final f in d.files.where((f) => f.isPdf)) {
          attachments.add(f.path);
        }
      }
      final j = File('${dir.path}/${c.reference}_case.json');
      await j.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'reference': c.reference,
        'requested': DateTime.now().toIso8601String(),
        'contact': {'name': _name.text, 'email': _email.text, 'phone': _phone.text, 'signing_date': _when.text},
        'paid_in_app': _paid,
        'community': c.community,
        'site': c.site,
        'notes': c.notes,
        'report': c.report,
      }));
      attachments.add(j.path);

      final r = c.report ?? {};
      final body = StringBuffer()
        ..writeln('Pre-purchase advice request – ${c.reference}')
        ..writeln()
        ..writeln('Name: ${_name.text.trim()}')
        ..writeln('Email: ${_email.text.trim()}')
        ..writeln('Phone: ${_phone.text.trim()}')
        ..writeln('Planning to sign around: ${_when.text.trim().isEmpty ? 'not stated' : _when.text.trim()}')
        ..writeln('Community / site: ${c.displayTitle}')
        ..writeln('Payment: ${_paid ? 'paid in app (check Stripe for ${c.reference})' : 'NOT PAID'}')
        ..writeln('Includes: 12 months ARPRA membership')
        ..writeln()
        ..writeln('App check: ${r['overall_rating'] ?? 'not run'} – ${r['overall_reason'] ?? ''}')
        ..writeln()
        ..writeln('Attached: the app report (PDF), each document, and the case data (JSON).')
        ..writeln('Sent from Before You Sign (test build) on ${DateFormat('d MMM yyyy h:mm a').format(DateTime.now())}.');

      if (_useServer) {
        final emailed = await _upload(attachments, {
          'contact': {'name': _name.text, 'email': _email.text, 'phone': _phone.text, 'signing_date': _when.text},
          'title': c.displayTitle,
          'rating': r['overall_rating'] ?? '',
          'rating_reason': r['overall_reason'] ?? '',
        });
        if (!mounted) return;
        setState(() => _sent = emailed);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(emailed ? 'Sent to ARPRA' : 'Received by ARPRA'),
            content: Text(emailed
                ? 'Your documents are with ARPRA (reference ${c.reference}). An adviser will contact you. '
                    'Please keep this reference.'
                : 'ARPRA has received your documents (reference ${c.reference}). They will be passed to an '
                    'adviser shortly. Please keep this reference.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        return;
      }

      final subject = 'Pre-purchase review request ${c.reference} – ${c.displayTitle}';
      try {
        await FlutterEmailSender.send(Email(
          recipients: [AppSettings.instance.arpraEmail],
          subject: subject,
          body: body.toString(),
          attachmentPaths: attachments,
        ));
      } catch (_) {
        // No email app that supports this: fall back to the share sheet.
        await SharePlus.instance.share(ShareParams(
          files: attachments.map((p) => XFile(p)).toList(),
          subject: subject,
          text: 'Send to: ${AppSettings.instance.arpraEmail}\n\n$body',
        ));
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      _snack(_useServer ? 'Could not send to ARPRA: $msg' : 'Could not prepare the email: $msg');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fee = AppSettings.instance.feeText;
    return Scaffold(
      appBar: AppBar(title: const Text('ARPRA review')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Get ARPRA to review your documents', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text(
            'You get the full report straight away. An ARPRA adviser will also read your documents in full, check them '
            'against the law, and send you written advice with the issues to raise before you sign. Your scanned documents and this report are sent '
            'to ARPRA, so you do not need to post anything.',
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFFEEF0FB),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fee.isEmpty ? 'Fee: to be confirmed (test build)' : fee,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
                const SizedBox(height: 6),
                const Row(children: [
                  Icon(Icons.card_membership, color: kAccent),
                  SizedBox(width: 8),
                  Expanded(child: Text('Includes 12 months\' free ARPRA membership')),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Text('1. Your details', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _field(_name, 'Your name(s)'),
          _field(_email, 'Email', type: TextInputType.emailAddress),
          _field(_phone, 'Phone', type: TextInputType.phone),
          _field(_when, 'When are you planning to sign? (optional)'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            title: const Text('I agree to my documents and details being sent to ARPRA for this review.'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 12),
          Text('2. Pay securely', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _detailsOk && !_paid && !_waiting ? _pay : null,
            icon: Icon(_paid ? Icons.check : Icons.lock_outline),
            label: Text(_paid ? (_testPayment ? 'Paid (test payment)' : 'Paid') : 'Pay with card (Stripe)'),
          ),
          if (_waiting && !_paid) ...[
            const SizedBox(height: 10),
            Row(children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              const Expanded(child: Text('Waiting for the payment to be confirmed…')),
              TextButton(onPressed: _checking ? null : () => _checkPaid(), child: const Text('Check now')),
            ]),
            TextButton(
              onPressed: () {
                _poll?.cancel();
                setState(() => _waiting = false);
              },
              child: const Text('I did not pay – go back'),
            ),
          ],
          const SizedBox(height: 16),
          Text('3. Send to ARPRA', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _detailsOk && _paid && !_sending && !_sent ? _send : null,
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send),
            label: Text(_sent ? 'Sent to ARPRA' : 'Send my documents'),
          ),
          const SizedBox(height: 8),
          Text(
            _useServer
                ? 'Your documents and this report are sent securely to ARPRA (reference ${c.reference}).'
                : 'Test build: this opens your email app with everything attached, addressed to '
                    '${AppSettings.instance.arpraEmail}. Just press Send.',
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctl, String label, {TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: ctl,
          keyboardType: type,
          decoration: InputDecoration(labelText: label),
          onChanged: (_) => setState(() {}),
        ),
      );
}
