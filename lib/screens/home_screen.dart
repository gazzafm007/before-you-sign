import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models.dart';
import '../sample.dart';
import '../settings.dart';
import 'check_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<CheckCase> _cases = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final all = await CaseStore.all();
    if (!mounted) return;
    setState(() {
      _cases = all;
      _loading = false;
    });
  }

  Future<void> _newCheck() async {
    final c = CheckCase.create();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CheckScreen(checkCase: c)));
    _refresh();
  }

  Future<void> _sample() async {
    final c = CheckCase.create()
      ..sample = true
      ..community = 'Riverbend Lakes Village (example)'
      ..site = '58'
      ..buyer = 'Pat Example'
      ..report = Map<String, dynamic>.from(kSampleReport)
      ..checkedAt = DateTime.now()
      ..model = 'sample';
    await CaseStore.save(c);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ReportScreen(checkCase: c)));
    _refresh();
  }

  Future<void> _open(CheckCase c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => c.report != null ? ReportScreen(checkCase: c) : CheckScreen(checkCase: c)),
    );
    _refresh();
  }

  Future<void> _delete(CheckCase c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this check?'),
        content: Text('${c.displayTitle}\n\nThe scanned pages and report will be removed from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await CaseStore.delete(c);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Before You Sign'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              setState(() {});
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!s.hasKey)
              Card(
                color: const Color(0xFFFFF4DE),
                child: ListTile(
                  leading: const Icon(Icons.info_outline, color: kAmber),
                  title: const Text('Test build'),
                  subtitle: const Text('Add the Claude API key in Settings to run real checks. You can try the sample report now.'),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                    setState(() {});
                  },
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.fact_check_outlined, size: 44, color: kAccent),
                    const SizedBox(height: 10),
                    Text('Check your land lease documents before you sign',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    const Text(
                      'Scan the Disclosure Statement, Site Agreement and Community Rules with your camera. '
                      'You will get a plain-English report: what it will cost, what to look closely at, and the questions to ask.',
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _newCheck,
                        icon: const Icon(Icons.document_scanner_outlined),
                        label: const Text('Start a new check'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _sample,
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('See a sample report'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Your checks', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_cases.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No checks yet.', style: TextStyle(color: Colors.black54)),
              )
            else
              ..._cases.map((c) => Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      title: Text(c.displayTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '${DateFormat('d MMM yyyy').format(c.created)} · '
                        '${c.report != null ? 'Report ready' : 'Not checked yet'}${c.sample ? ' · sample' : ''}',
                      ),
                      leading: _RatingDot(rating: c.report?['overall_rating'] as String?),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'delete') _delete(c);
                          if (v == 'docs') {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => CheckScreen(checkCase: c)))
                                .then((_) => _refresh());
                          }
                        },
                        itemBuilder: (_) => [
                          if (!c.sample) const PopupMenuItem(value: 'docs', child: Text('Documents / check again')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                      onTap: () => _open(c),
                    ),
                  )),
            const SizedBox(height: 24),
            const Text(
              'Before You Sign is a first check, not legal advice. ARPRA Limited · 1300 798 399',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingDot extends StatelessWidget {
  final String? rating;
  const _RatingDot({this.rating});
  @override
  Widget build(BuildContext context) {
    final color = switch (rating) {
      'High' => kRed,
      'Moderate' => kAmber,
      'Low' => kGreen,
      _ => Colors.grey,
    };
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: .12),
      child: Icon(rating == null ? Icons.description_outlined : Icons.flag, color: color),
    );
  }
}
