import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models.dart';

const _ink = PdfColor.fromInt(0xFF1B1F2A);
const _accent = PdfColor.fromInt(0xFF2326C9);
const _red = PdfColor.fromInt(0xFFB3261E);
const _redBg = PdfColor.fromInt(0xFFFCEBEA);
const _amber = PdfColor.fromInt(0xFF8A5300);
const _amberBg = PdfColor.fromInt(0xFFFFF4DE);
const _green = PdfColor.fromInt(0xFF1E6B3A);
const _greenBg = PdfColor.fromInt(0xFFE6F4EA);
const _muted = PdfColor.fromInt(0xFF5B6170);
const _line = PdfColor.fromInt(0xFFDADCE3);

List _list(dynamic v) => v is List ? v : const [];
String _s(dynamic v) => v == null ? '' : v.toString();

/// Builds the printable/emailable report and returns the file.
Future<File> buildReportPdf(CheckCase c, Directory outDir) async {
  final r = c.report ?? {};
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/AtkinsonHyperlegible-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/AtkinsonHyperlegible-Bold.ttf'));
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  final doc = pw.Document(theme: theme, title: 'Before You Sign report ${c.reference}', author: 'ARPRA Limited');

  final date = DateFormat('d MMMM yyyy').format(c.checkedAt ?? DateTime.now());
  final rating = _s(r['overall_rating']);
  final ratingColor = rating == 'High' ? _red : rating == 'Low' ? _green : _amber;

  pw.Widget h(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _accent)),
      );
  pw.Widget p(String t, {double size = 10.5, PdfColor color = _ink}) =>
      pw.Text(t, style: pw.TextStyle(fontSize: size, color: color, lineSpacing: 2));

  pw.Widget item(Map m, PdfColor fg, PdfColor bg) => pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 6),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: bg,
          border: pw.Border(left: pw.BorderSide(color: fg, width: 3)),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(_s(m['title']), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink)),
          if (_s(m['detail']).isNotEmpty) pw.SizedBox(height: 2),
          if (_s(m['detail']).isNotEmpty) p(_s(m['detail']), size: 10),
          if (_s(m['where']).isNotEmpty)
            pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: p('Where: ${_s(m['where'])}', size: 9, color: _muted)),
          if (_s(m['ask']).isNotEmpty)
            pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: p('Ask: ${_s(m['ask'])}', size: 9.5, color: fg)),
        ]),
      );

  pw.Widget row(String k, String v) => v.isEmpty
      ? pw.SizedBox()
      : pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 120, child: p(k, size: 10, color: _muted)),
            pw.Expanded(child: p(v, size: 10.5)),
          ]),
        );

  final costs = (r['costs'] is Map) ? r['costs'] as Map : {};

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 40),
    header: (ctx) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line))),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Before You Sign · ARPRA', style: pw.TextStyle(fontSize: 9, color: _accent, fontWeight: pw.FontWeight.bold)),
        pw.Text('${c.reference} · $date', style: const pw.TextStyle(fontSize: 9, color: _muted)),
      ]),
    ),
    footer: (ctx) => pw.Column(children: [
      pw.Text(
        'This is an automated first check, not legal or financial advice. ARPRA Limited · 1300 798 399 · www.arpra.org.au',
        style: const pw.TextStyle(fontSize: 8, color: _muted),
      ),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
      ),
    ]),
    build: (ctx) => [
      pw.Text('Pre-purchase document check', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _ink)),
      pw.SizedBox(height: 4),
      p(c.displayTitle, size: 13),
      if (_s(r['operator']).isNotEmpty) p('Operator: ${_s(r['operator'])}', size: 10, color: _muted),
      if (_s(r['buyer']).isNotEmpty || c.buyer.isNotEmpty)
        p('Prepared for: ${c.buyer.isNotEmpty ? c.buyer : _s(r['buyer'])}', size: 10, color: _muted),
      if (c.sample) p('SAMPLE REPORT — fictional community, for demonstration only', size: 10, color: _red),
      if (c.asAt != null) p('ARPRA TEST — checked as at ${DateFormat('d MMMM yyyy').format(c.asAt!)}', size: 10, color: _red),
      pw.SizedBox(height: 10),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: ratingColor, width: 1.5), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Overall concern: $rating', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: ratingColor)),
          if (_s(r['overall_reason']).isNotEmpty) p(_s(r['overall_reason'])),
          pw.SizedBox(height: 6),
          p(_s(r['summary'])),
        ]),
      ),
      if (_list(r['top_issues']).isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _accent, width: 1.5), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('The things that matter most', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _accent)),
            pw.SizedBox(height: 4),
            ..._list(r['top_issues']).asMap().entries.map((e) {
              final m = e.value is Map ? e.value as Map : {'title': e.value};
              return pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('${e.key + 1}. ${_s(m['title'])}', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
                  if (_s(m['why']).isNotEmpty) p(_s(m['why']), size: 10),
                  if (_s(m['ask']).isNotEmpty) p('Ask: ${_s(m['ask'])}', size: 10, color: _muted),
                ]),
              );
            }),
          ]),
        ),
      ],
      h('What it will cost'),
      row('Proposed site fee', _s(costs['proposed_fee'])),
      row('Current fee for site', _s(costs['current_fee'])),
      row('Range in community', _s(costs['community_range'])),
      row('Increase method', _s(costs['increase_method'])),
      row('First increase', _s(costs['first_increase'])),
      if (_list(costs['projection']).isNotEmpty) ...[
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: ['When', 'Weekly site fee'],
          data: _list(costs['projection']).map((e) => [_s((e as Map)['when']), _s(e['weekly'])]).toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEF0FB)),
          border: pw.TableBorder.all(color: _line, width: .5),
          cellAlignments: {1: pw.Alignment.centerRight},
        ),
      ],
      if (_list(costs['other_costs']).isNotEmpty) ...[
        pw.SizedBox(height: 6),
        p('Other costs', size: 10, color: _muted),
        ..._list(costs['other_costs']).map((e) => pw.Bullet(text: _s(e), style: const pw.TextStyle(fontSize: 10))),
      ],
      if (_list(r['key_dates']).isNotEmpty) ...[
        h('Key dates'),
        ..._list(r['key_dates']).map((e) => row(_s((e as Map)['date']), _s(e['what']))),
      ],
      if (_list(r['red']).isNotEmpty) ...[
        h('Look closely before you sign'),
        ..._list(r['red']).map((e) => item(e as Map, _red, _redBg)),
      ],
      if (_list(r['amber']).isNotEmpty) ...[
        h('Ask about'),
        ..._list(r['amber']).map((e) => item(e as Map, _amber, _amberBg)),
      ],
      if (_list(r['green']).isNotEmpty) ...[
        h('Looks usual'),
        ..._list(r['green']).map((e) => item(e as Map, _green, _greenBg)),
      ],
      if (_list(r['standard_terms_changes']).isNotEmpty) ...[
        h('Changes to the standard terms'),
        pw.TableHelper.fromTextArray(
          headers: ['Clause', 'Standard form says', 'This agreement says', 'Effect'],
          data: _list(r['standard_terms_changes']).map((e) {
            final m = e as Map;
            final status = _s(m['status']);
            return [
              [_s(m['clause']), status].where((x) => x.isNotEmpty).join('\n'),
              _s(m['prescribed']),
              _s(m['document_says']),
              _s(m['effect']),
            ];
          }).toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEF0FB)),
          border: pw.TableBorder.all(color: _line, width: .5),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.2),
            1: const pw.FlexColumnWidth(2.5),
            2: const pw.FlexColumnWidth(2.5),
            3: const pw.FlexColumnWidth(2.5),
          },
        ),
      ],
      if (_list(r['tick_boxes']).isNotEmpty) ...[
        h('Tick-boxes'),
        pw.TableHelper.fromTextArray(
          headers: ['Where', 'Box group', 'Marked', 'Check'],
          data: _list(r['tick_boxes']).map((e) {
            final m = e as Map;
            final status = _s(m['status']);
            return [
              [_s(m['document']), _s(m['page']).isEmpty ? '' : 'p ${_s(m['page'])}']
                  .where((x) => x.isNotEmpty)
                  .join(', '),
              _s(m['group']),
              _s(m['ticked']).isEmpty ? 'nothing' : _s(m['ticked']),
              status == 'ok' ? 'OK' : [status, _s(m['issue'])].where((x) => x.isNotEmpty).join(': '),
            ];
          }).toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEF0FB)),
          border: pw.TableBorder.all(color: _line, width: .5),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.5),
            1: const pw.FlexColumnWidth(2.5),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(3),
          },
        ),
      ],
      if (_list(r['blanks']).isNotEmpty) ...[
        h('Blank or incomplete'),
        ..._list(r['blanks']).map((e) {
          final m = e as Map;
          final where = [_s(m['document']), _s(m['page']).isEmpty ? '' : 'p ${_s(m['page'])}']
              .where((x) => x.isNotEmpty)
              .join(', ');
          final why = _s(m['why']);
          return pw.Bullet(
              text: '${_s(m['field'])} — $where${why.isEmpty ? '' : '. $why'}',
              style: const pw.TextStyle(fontSize: 10));
        }),
      ],
      if (_list(r['questions']).isNotEmpty) ...[
        h('Questions to ask the operator'),
        ..._list(r['questions']).asMap().entries.map((e) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: p('${e.key + 1}. ${_s(e.value)}'))),
      ],
      h('Documents checked'),
      ..._list(r['documents_reviewed']).map((e) => pw.Bullet(
          text: [_s((e as Map)['name']), _s(e['date']), _s(e['notes'])].where((x) => x.isNotEmpty).join(' — '),
          style: const pw.TextStyle(fontSize: 10))),
      if (_list(r['documents_missing']).isNotEmpty) ...[
        pw.SizedBox(height: 4),
        p('Not provided: ${_list(r['documents_missing']).map(_s).join('; ')}', size: 10, color: _muted),
      ],
      pw.SizedBox(height: 14),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        color: const PdfColor.fromInt(0xFFEEF0FB),
        child: p(
          'Want ARPRA to review your documents? ARPRA\'s pre-purchase advice service checks your documents in detail, '
          'raises the issues with you in writing and includes 12 months\' ARPRA membership. '
          'Call 1300 798 399 or use "Get ARPRA to review" in the app.',
          size: 10,
        ),
      ),
      pw.SizedBox(height: 8),
      p('About this report: it was produced automatically from the documents you scanned on ${DateFormat('d MMMM yyyy').format(c.checkedAt ?? DateTime.now())}. '
          'It may miss things or misread a page. It is general information, not legal or financial advice. '
          'Check anything important with ARPRA, a solicitor or NSW Fair Trading (13 32 20) before you sign.',
          size: 8.5, color: _muted),
    ],
  ));

  // Keep the file name short: Android refuses names over 255 bytes, and the
  // community name in a report can be a whole sentence.
  var safe = c.displayTitle.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  if (safe.length > 40) safe = safe.substring(0, 40);
  safe = safe.replaceAll(RegExp(r'^_+|_+$'), '');
  final f = File('${outDir.path}/BeforeYouSign_${safe}_${c.reference}.pdf');
  await f.writeAsBytes(await doc.save());
  return f;
}

/// Puts the photographed pages of one document into a single PDF so they can
/// be emailed to ARPRA as one attachment.
Future<File?> pagesToPdf(CaseDoc d, Directory outDir, String ref) async {
  final photos = d.files.where((f) => !f.isPdf).toList();
  if (photos.isEmpty) return null;
  final doc = pw.Document(title: '${d.kind.title} $ref');
  for (final f in photos) {
    final image = pw.MemoryImage(await File(f.path).readAsBytes());
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(12),
      build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
    ));
  }
  final out = File('${outDir.path}/${ref}_${d.kind.short}_scanned.pdf');
  await out.writeAsBytes(await doc.save());
  return out;
}
