import 'dart:async';

import 'package:flutter/material.dart';

import '../analyzer.dart';
import '../main.dart';
import '../models.dart';
import '../settings.dart';
import 'check_screen.dart';
import 'report_screen.dart';

class ProgressScreen extends StatefulWidget {
  final CheckCase checkCase;
  const ProgressScreen({super.key, required this.checkCase});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final _analyzer = Analyzer();
  int _chars = 0;
  String? _error;
  final _started = DateTime.now();
  Timer? _tick;

  static const _expectedChars = 11000;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    _go();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _analyzer.cancel();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _error = null;
      _chars = 0;
    });
    final c = widget.checkCase;
    try {
      final report = await _analyzer.run(c, onProgress: (n) {
        if (mounted) setState(() => _chars = n);
      });
      c.report = report;
      c.checkedAt = DateTime.now();
      c.model = AppSettings.instance.model;
      await CaseStore.save(c);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ReportScreen(checkCase: c)));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final secs = DateTime.now().difference(_started).inSeconds;
    final writing = _chars > 0;
    final frac = writing ? (_chars / _expectedChars).clamp(0.05, 0.97) : null;
    final stage = !writing
        ? (secs < 20 ? 'Sending your documents…' : 'Reading every page — this usually takes 1 to 3 minutes…')
        : 'Writing your report…';

    return Scaffold(
      appBar: AppBar(title: const Text('Checking'), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _error != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: kRed, size: 48),
                  const SizedBox(height: 12),
                  Text('The check did not finish', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(_error!),
                  const Spacer(),
                  FilledButton(onPressed: _go, child: const Text('Try again')),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.pushReplacement(
                        context, MaterialPageRoute(builder: (_) => CheckScreen(checkCase: widget.checkCase))),
                    child: const Text('Back to my documents'),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.fact_check_outlined, size: 64, color: kAccent),
                  const SizedBox(height: 24),
                  Text(stage, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 20),
                  LinearProgressIndicator(value: frac, minHeight: 10, borderRadius: BorderRadius.circular(6)),
                  const SizedBox(height: 12),
                  Text('${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 28),
                  const Text(
                    'Keep the app open. We are checking the fees, the increase method, extra terms, the rules, '
                    'key dates and anything left blank.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  TextButton(
                    onPressed: () {
                      _analyzer.cancel();
                      Navigator.pushReplacement(
                          context, MaterialPageRoute(builder: (_) => CheckScreen(checkCase: widget.checkCase)));
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              ),
      ),
    );
  }
}
