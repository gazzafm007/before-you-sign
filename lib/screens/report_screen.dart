import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart';
import '../models.dart';
import '../report_pdf.dart';
import 'upgrade_screen.dart';

List _list(dynamic v) => v is List ? v : const [];
String _s(dynamic v) => v == null ? '' : v.toString();

class ReportScreen extends StatefulWidget {
  final CheckCase checkCase;
  const ReportScreen({super.key, required this.checkCase});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  CheckCase get c => widget.checkCase;
  Map<String, dynamic> get r => c.report ?? {};
  bool _sharing = false;

  Future<Directory> _outDir() async {
    final d = Directory('${(await getTemporaryDirectory()).path}/share_${c.id}');
    if (await d.exists()) await d.delete(recursive: true);
    await d.create(recursive: true);
    return d;
  }

  Future<void> _sharePdf({bool withData = false}) async {
    setState(() => _sharing = true);
    try {
      final dir = await _outDir();
      final pdf = await buildReportPdf(c, dir);
      final files = [XFile(pdf.path, mimeType: 'application/pdf')];
      if (withData) {
        final j = File('${dir.path}/${c.reference}_report_data.json');
        await j.writeAsString(const JsonEncoder.withIndent('  ').convert({
          'reference': c.reference,
          'checkedAt': c.checkedAt?.toIso8601String(),
          'model': c.model,
          'community': c.community,
          'site': c.site,
          'documents': c.docs
              .where((d) => !d.isEmpty)
              .map((d) => {'kind': d.kind.title, 'files': d.files.map((f) => f.name).toList()})
              .toList(),
          'report': r,
        }));
        files.add(XFile(j.path, mimeType: 'application/json'));
      }
      await SharePlus.instance.share(ShareParams(
        files: files,
        subject: 'Before You Sign report – ${c.displayTitle}',
        text: 'My Before You Sign report for ${c.displayTitle} (ref ${c.reference}).',
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create the report: $e')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final costs = r['costs'] is Map ? r['costs'] as Map : {};
    final rating = _s(r['overall_rating']);
    final (fg, bg) = switch (rating) {
      'High' => (kRed, kRedBg),
      'Low' => (kGreen, kGreenBg),
      _ => (kAmber, kAmberBg),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your report'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _sharePdf();
              if (v == 'data') _sharePdf(withData: true);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Share or email the report (PDF)')),
              PopupMenuItem(value: 'data', child: Text('Export for checking (PDF + data)')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 150),
        children: [
          Text(c.displayTitle, style: Theme.of(context).textTheme.titleLarge),
          if (_s(r['operator']).isNotEmpty)
            Text('Operator: ${_s(r['operator'])}', style: const TextStyle(color: Colors.black54)),
          Text(
            'Checked ${DateFormat('d MMMM yyyy').format(c.checkedAt ?? c.created)} · ref ${c.reference}',
            style: const TextStyle(color: Colors.black54, fontSize: 14),
          ),
          if (c.asAt != null)
            Text('Test: checked as at ${DateFormat('d MMMM yyyy').format(c.asAt!)}',
                style: const TextStyle(color: kRed, fontWeight: FontWeight.bold, fontSize: 14)),
          if (c.sample)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Sample report — fictional community', style: TextStyle(color: kRed, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: fg.withValues(alpha: .5)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.flag, color: fg),
                const SizedBox(width: 8),
                Text('Overall concern: $rating',
                    style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 19)),
              ]),
              if (_s(r['overall_reason']).isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(_s(r['overall_reason'])),
              ],
              const SizedBox(height: 10),
              Text(_s(r['summary'])),
            ]),
          ),
          if (_list(r['top_issues']).isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kAccent, width: 2),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('The ${_list(r['top_issues']).length == 1 ? 'thing' : '${_list(r['top_issues']).length} things'} that matter most',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: kAccent)),
                const SizedBox(height: 10),
                ..._list(r['top_issues']).asMap().entries.map((e) {
                  final m = e.value is Map ? e.value as Map : {'title': e.value};
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
                        child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_s(m['title']), style: const TextStyle(fontWeight: FontWeight.bold)),
                          if (_s(m['why']).isNotEmpty) Text(_s(m['why'])),
                          if (_s(m['ask']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('Ask: ${_s(m['ask'])}', style: const TextStyle(fontStyle: FontStyle.italic)),
                            ),
                        ]),
                      ),
                    ]),
                  );
                }),
              ]),
            ),
          ],
          _Section(
            icon: Icons.payments_outlined,
            title: 'What it will cost',
            initiallyExpanded: true,
            children: [
              _kv('Proposed site fee', costs['proposed_fee']),
              _kv('Current fee for this site', costs['current_fee']),
              _kv('Range in the community', costs['community_range']),
              _kv('How it increases', costs['increase_method']),
              _kv('First increase', costs['first_increase']),
              if (_list(costs['projection']).isNotEmpty) ...[
                const SizedBox(height: 8),
                Table(
                  border: TableBorder.all(color: const Color(0xFFDADCE3)),
                  columnWidths: const {1: IntrinsicColumnWidth()},
                  children: [
                    const TableRow(
                      decoration: BoxDecoration(color: Color(0xFFEEF0FB)),
                      children: [_Cell('When', bold: true), _Cell('Weekly fee', bold: true)],
                    ),
                    ..._list(costs['projection'])
                        .map((e) => TableRow(children: [_Cell(_s((e as Map)['when'])), _Cell(_s(e['weekly']))])),
                  ],
                ),
              ],
              if (_list(costs['other_costs']).isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Other costs', style: TextStyle(fontWeight: FontWeight.bold)),
                ..._list(costs['other_costs']).map((e) => _bullet(_s(e))),
              ],
            ],
          ),
          if (_list(r['key_dates']).isNotEmpty)
            _Section(
              icon: Icons.event_outlined,
              title: 'Key dates',
              initiallyExpanded: true,
              children: _list(r['key_dates']).map((e) => _kv(_s((e as Map)['date']), e['what'])).toList(),
            ),
          _items('Look closely before you sign', Icons.warning_amber_rounded, r['red'], kRed, kRedBg, true),
          _items('Ask about', Icons.help_outline, r['amber'], kAmber, kAmberBg, true),
          _items('Looks usual', Icons.check_circle_outline, r['green'], kGreen, kGreenBg, false),
          if (_list(r['standard_terms_changes']).isNotEmpty)
            _Section(
              icon: Icons.compare_arrows,
              title: 'Changes to the standard terms (${_changeCount(r)})',
              initiallyExpanded: _changeCount(r) > 0,
              children: _list(r['standard_terms_changes']).map((e) {
                final m = e as Map;
                final status = _s(m['status']);
                final lines = <String>[
                  if (_s(m['prescribed']).isNotEmpty) 'Standard form: “${_s(m['prescribed'])}”',
                  if (_s(m['document_says']).isNotEmpty) 'This agreement: “${_s(m['document_says'])}”',
                  if (_s(m['effect']).isNotEmpty) _s(m['effect']),
                ];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      [_s(m['clause']), status].where((x) => x.isNotEmpty).join(' — '),
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: _isChange(status) ? kRed : Colors.black87),
                    ),
                    ...lines.map((l) => Padding(padding: const EdgeInsets.only(top: 2), child: Text(l))),
                  ]),
                );
              }).toList(),
            ),
          if (_list(r['tick_boxes']).isNotEmpty)
            _Section(
              icon: Icons.check_box_outlined,
              title: 'Tick-boxes (${_tickProblems(r)} to check)',
              initiallyExpanded: _tickProblems(r) > 0,
              children: _list(r['tick_boxes']).map((e) {
                final m = e as Map;
                final status = _s(m['status']);
                final bad = status != 'ok';
                final where = [_s(m['document']), _s(m['page']).isEmpty ? '' : 'p ${_s(m['page'])}']
                    .where((x) => x.isNotEmpty)
                    .join(', ');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(bad ? Icons.error_outline : Icons.check, size: 20, color: bad ? kAmber : kGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_s(m['group']), style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Marked: ${_s(m['ticked']).isEmpty ? 'nothing' : _s(m['ticked'])}'
                            '${where.isEmpty ? '' : ' ($where)'}'),
                        if (_s(m['issue']).isNotEmpty) Text(_s(m['issue']), style: TextStyle(color: kAmber)),
                      ]),
                    ),
                  ]),
                );
              }).toList(),
            ),
          if (_list(r['blanks']).isNotEmpty)
            _Section(
              icon: Icons.edit_note,
              title: 'Blank or incomplete (${_list(r['blanks']).length})',
              children: _list(r['blanks']).map((e) {
                final m = e as Map;
                final where = [_s(m['document']), _s(m['page']).isEmpty ? '' : 'p ${_s(m['page'])}']
                    .where((x) => x.isNotEmpty)
                    .join(', ');
                final why = _s(m['why']);
                return _bullet('${_s(m['field'])} — $where${why.isEmpty ? '' : '. $why'}');
              }).toList(),
            ),
          if (_list(r['questions']).isNotEmpty)
            _Section(
              icon: Icons.question_answer_outlined,
              title: 'Questions to ask the operator',
              initiallyExpanded: true,
              children: _list(r['questions'])
                  .asMap()
                  .entries
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('${e.key + 1}. ${_s(e.value)}'),
                      ))
                  .toList(),
            ),
          _Section(
            icon: Icons.folder_open,
            title: 'Documents checked',
            children: [
              ..._list(r['documents_reviewed']).map((e) => _bullet(
                  [_s((e as Map)['name']), _s(e['date']), _s(e['notes'])].where((x) => x.isNotEmpty).join(' — '))),
              if (_list(r['documents_missing']).isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Not provided: ${_list(r['documents_missing']).map(_s).join('; ')}',
                    style: const TextStyle(color: Colors.black54)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'This is an automated first check, not legal or financial advice. It may miss things or misread a page. '
            'Check anything important with ARPRA, a solicitor or NSW Fair Trading (13 32 20) before you sign.',
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFDADCE3))),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UpgradeScreen(checkCase: c))),
              icon: const Icon(Icons.support_agent),
              label: const Text('Get ARPRA to review this'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _sharing ? null : () => _sharePdf(),
              icon: _sharing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.ios_share),
              label: const Text('Email or share the report'),
            ),
          ]),
        ),
      ),
    );
  }

  static bool _isChange(String status) =>
      const ['changed', 'missing', 'added', 'old version'].contains(status.toLowerCase());

  int _changeCount(Map r) =>
      _list(r['standard_terms_changes']).where((e) => _isChange(_s((e as Map)['status']))).length;

  int _tickProblems(Map r) =>
      _list(r['tick_boxes']).where((e) => _s((e as Map)['status']) != 'ok').length;

  Widget _kv(String k, dynamic v) {
    final t = _s(v);
    if (t.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: const TextStyle(fontSize: 14.5, color: Colors.black54)),
        Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _bullet(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('•  '),
          Expanded(child: Text(t)),
        ]),
      );

  Widget _items(String title, IconData icon, dynamic items, Color fg, Color bg, bool open) {
    final l = _list(items);
    if (l.isEmpty) return const SizedBox.shrink();
    return _Section(
      icon: icon,
      iconColor: fg,
      title: '$title (${l.length})',
      initiallyExpanded: open,
      children: l.map((e) {
        final m = e as Map;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: fg, width: 4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_s(m['title']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17.5)),
            if (basisLabel(m['basis'], m['law']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: fg.withValues(alpha: .6)),
                  ),
                  child: Text(basisLabel(m['basis'], m['law']),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: fg)),
                ),
              ),
            if (_s(m['detail']).isNotEmpty) ...[const SizedBox(height: 4), Text(_s(m['detail']))],
            if (_s(m['where']).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_s(m['where']), style: const TextStyle(fontSize: 14, color: Colors.black54)),
            ],
            if (_s(m['ask']).isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Ask: ${_s(m['ask'])}', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
            ],
          ]),
        );
      }).toList(),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
    this.iconColor,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: Icon(icon, color: iconColor ?? kAccent),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String t;
  final bool bold;
  const _Cell(this.t, {this.bold = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(t, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      );
}
