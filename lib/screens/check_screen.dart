import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

import '../analyzer.dart';
import '../main.dart';
import '../models.dart';
import '../settings.dart';
import 'progress_screen.dart';

class CheckScreen extends StatefulWidget {
  final CheckCase checkCase;
  const CheckScreen({super.key, required this.checkCase});
  @override
  State<CheckScreen> createState() => _CheckScreenState();
}

class _CheckScreenState extends State<CheckScreen> {
  late final CheckCase c = widget.checkCase;
  late final _community = TextEditingController(text: c.community);
  late final _site = TextEditingController(text: c.site);
  late final _buyer = TextEditingController(text: c.buyer);
  late final _notes = TextEditingController(text: c.notes);
  DocKind? _busy;

  @override
  void dispose() {
    _community.dispose();
    _site.dispose();
    _buyer.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _persist() async {
    c.community = _community.text.trim();
    c.site = _site.text.trim();
    c.buyer = _buyer.text.trim();
    c.notes = _notes.text.trim();
    await CaseStore.save(c);
  }

  String _stamp() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _scan(CaseDoc d) async {
    setState(() => _busy = d.kind);
    try {
      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormats: {DocumentFormat.jpeg},
          pageLimit: 60,
          mode: ScannerMode.full,
          isGalleryImport: true,
        ),
      );
      final result = await scanner.scanDocument();
      await scanner.close();
      final dir = await CaseStore.folder(c);
      for (final p in result.images ?? <String>[]) {
        final src = p.startsWith('file:') ? Uri.parse(p).toFilePath() : p;
        final dest = '${dir.path}/${d.kind.short}_${_stamp()}.jpg';
        await preparePhoto(src, dest);
        d.files.add(DocFile(dest, false));
      }
      await _persist();
    } catch (e) {
      if (!mounted) return;
      // Show a short reason, not the whole Android stack trace.
      var msg = e is PlatformException ? (e.message ?? e.code) : e.toString();
      msg = msg.split('\n').first;
      if (msg.length > 160) msg = '${msg.substring(0, 160)}…';
      if (!msg.toLowerCase().contains('cancel')) {
        _snack('The scanner could not start. You can use "Add a file" instead.\n($msg)');
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _addFile(CaseDoc d) async {
    setState(() => _busy = d.kind);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );
      final dir = await CaseStore.folder(c);
      for (final f in picked) {
        final bytes = await f.xFile.readAsBytes();
        final ext = (f.extension ?? '').toLowerCase();
        if (ext == 'pdf') {
          final safe = f.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
          final dest = '${dir.path}/${d.kind.short}_${_stamp()}_$safe';
          await File(dest).writeAsBytes(bytes);
          d.files.add(DocFile(dest, true));
        } else {
          final tmp = '${dir.path}/tmp_${_stamp()}.$ext';
          await File(tmp).writeAsBytes(bytes);
          final dest = '${dir.path}/${d.kind.short}_${_stamp()}.jpg';
          await preparePhoto(tmp, dest);
          await File(tmp).delete();
          d.files.add(DocFile(dest, false));
        }
      }
      await _persist();
    } catch (e) {
      if (mounted) _snack('Could not add that file. ($e)');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _remove(CaseDoc d, DocFile f) async {
    d.files.remove(f);
    try {
      await File(f.path).delete();
    } catch (_) {}
    await _persist();
    if (mounted) setState(() {});
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run() async {
    await _persist();
    if (!mounted) return;
    if (!AppSettings.instance.hasKey) {
      _snack('Add the Claude API key in Settings first (test build).');
      return;
    }
    if (c.doc(DocKind.disclosure).isEmpty || c.doc(DocKind.siteAgreement).isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Some documents are missing'),
          content: const Text(
              'For the best check, add both the Disclosure Statement and the Site Agreement. '
              'Do you want to check what you have so far?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Add more')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Check now')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    if (!mounted) return;
    await Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProgressScreen(checkCase: c)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (_, _) => _persist(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Your documents')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            const Text('Add each document you have been given. Scan every page, front and back if printed both sides.'),
            const SizedBox(height: 14),
            ...c.docs.map(_docCard),
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Your details (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
              children: [
                _field(_community, 'Community name'),
                _field(_site, 'Site number'),
                _field(_buyer, 'Your name(s) for the report'),
                _field(_notes, 'Anything we should know? (e.g. "home not built yet", "I have a dog")', lines: 3),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'When you tap Check, your documents are sent securely to the Claude AI service to be read. '
              'They are not sent to the operator. The report stays on this phone unless you share it.',
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: c.hasAnyDoc && _busy == null ? _run : null,
              icon: const Icon(Icons.fact_check),
              label: Text(c.report == null ? 'Check my documents' : 'Check again'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctl, String label, {int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: ctl,
          minLines: lines,
          maxLines: lines,
          decoration: InputDecoration(labelText: label),
          onChanged: (_) => setState(() {}),
        ),
      );

  Widget _docCard(CaseDoc d) {
    final done = !d.isEmpty;
    final busy = _busy == d.kind;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? kGreen : Colors.black38),
              const SizedBox(width: 10),
              Expanded(child: Text(d.kind.title, style: Theme.of(context).textTheme.titleMedium)),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 2),
              child: Text(d.kind.hint, style: const TextStyle(fontSize: 14.5, color: Colors.black54)),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 4),
              child: Text(d.countText, style: TextStyle(fontWeight: FontWeight.bold, color: done ? kGreen : Colors.black45)),
            ),
            if (done) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 92,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: d.files.map((f) => _thumb(d, f)).toList(),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (busy)
              const LinearProgressIndicator()
            else
              Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy == null ? () => _scan(d) : null,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Scan pages'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy == null ? () => _addFile(d) : null,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Add a file'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
                  ),
                ),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _thumb(CaseDoc d, DocFile f) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 70,
            height: 92,
            color: const Color(0xFFEEF0FB),
            child: f.isPdf
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.picture_as_pdf, color: kRed, size: 30),
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(f.name.replaceFirst(RegExp(r'^[A-Za-z]+_\d+_'), ''),
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                    ),
                  ])
                : Image.file(File(f.path), fit: BoxFit.cover, cacheWidth: 160),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: InkWell(
            onTap: () => _remove(d, f),
            child: Container(
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              padding: const EdgeInsets.all(3),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ]),
    );
  }
}
