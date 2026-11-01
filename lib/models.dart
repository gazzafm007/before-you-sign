import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// The kinds of document a buyer can add.
enum DocKind { disclosure, siteAgreement, rules, contract, other }

extension DocKindText on DocKind {
  String get title => switch (this) {
        DocKind.disclosure => 'Disclosure Statement',
        DocKind.siteAgreement => 'Site Agreement',
        DocKind.rules => 'Community Rules',
        DocKind.contract => 'Contract for the home',
        DocKind.other => 'Other document',
      };
  String get hint => switch (this) {
        DocKind.disclosure => 'Must be given to you at least 14 days before you sign',
        DocKind.siteAgreement => 'Also called the Residential Site Agreement',
        DocKind.rules => 'Also called Park Rules or Village Rules',
        DocKind.contract => 'Contract for sale or Home Purchase Agreement (if any)',
        DocKind.other => 'Site plan, brochure, letter from the operator…',
      };
  String get short => switch (this) {
        DocKind.disclosure => 'DS',
        DocKind.siteAgreement => 'RSA',
        DocKind.rules => 'Rules',
        DocKind.contract => 'Contract',
        DocKind.other => 'Other',
      };
}

/// One file belonging to a document: either a page photo (jpg) or a PDF.
class DocFile {
  final String path;
  final bool isPdf;
  DocFile(this.path, this.isPdf);
  Map<String, dynamic> toJson() => {'path': path, 'pdf': isPdf};
  factory DocFile.fromJson(Map<String, dynamic> j) =>
      DocFile(j['path'] as String, j['pdf'] as bool? ?? false);
  String get name => path.split(Platform.pathSeparator).last;
}

class CaseDoc {
  final DocKind kind;
  final List<DocFile> files;
  CaseDoc(this.kind, [List<DocFile>? files]) : files = files ?? [];
  int get photoCount => files.where((f) => !f.isPdf).length;
  int get pdfCount => files.where((f) => f.isPdf).length;
  bool get isEmpty => files.isEmpty;
  String get countText {
    final parts = <String>[];
    if (photoCount > 0) parts.add('$photoCount page${photoCount == 1 ? '' : 's'} scanned');
    if (pdfCount > 0) parts.add('$pdfCount PDF${pdfCount == 1 ? '' : 's'}');
    return parts.isEmpty ? 'Not added yet' : parts.join(' · ');
  }

  Map<String, dynamic> toJson() =>
      {'kind': kind.name, 'files': files.map((f) => f.toJson()).toList()};
  factory CaseDoc.fromJson(Map<String, dynamic> j) => CaseDoc(
      DocKind.values.byName(j['kind'] as String),
      (j['files'] as List).map((e) => DocFile.fromJson(e)).toList());
}

/// A single check: the documents, the buyer's details and (once done) the report.
class CheckCase {
  final String id;
  final DateTime created;
  String community;
  String site;
  String buyer;
  String notes;
  final List<CaseDoc> docs;
  Map<String, dynamic>? report;
  String? model;
  DateTime? checkedAt;
  bool sample;

  CheckCase({
    required this.id,
    required this.created,
    this.community = '',
    this.site = '',
    this.buyer = '',
    this.notes = '',
    List<CaseDoc>? docs,
    this.report,
    this.model,
    this.checkedAt,
    this.sample = false,
  }) : docs = docs ??
            [
              CaseDoc(DocKind.disclosure),
              CaseDoc(DocKind.siteAgreement),
              CaseDoc(DocKind.rules),
              CaseDoc(DocKind.contract),
              CaseDoc(DocKind.other),
            ];

  factory CheckCase.create() =>
      CheckCase(id: const Uuid().v4().substring(0, 8).toUpperCase(), created: DateTime.now());

  CaseDoc doc(DocKind k) => docs.firstWhere((d) => d.kind == k);
  bool get hasAnyDoc => docs.any((d) => !d.isEmpty);
  String get reference => 'BYS-$id';

  String get displayTitle {
    var c = (report?['community'] as String?)?.trim().isNotEmpty == true
        ? report!['community'] as String
        : community;
    var s = (report?['site'] as String?)?.trim().isNotEmpty == true
        ? report!['site'] as String
        : site;
    if (c.length > 60) c = '${c.substring(0, 57)}…';
    if (s.length > 20) s = '${s.substring(0, 17)}…';
    if (c.isEmpty && s.isEmpty) return 'Check $reference';
    if (s.isEmpty) return c;
    return c.isEmpty ? 'Site $s' : '$c · Site $s';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'created': created.toIso8601String(),
        'community': community,
        'site': site,
        'buyer': buyer,
        'notes': notes,
        'docs': docs.map((d) => d.toJson()).toList(),
        'report': report,
        'model': model,
        'checkedAt': checkedAt?.toIso8601String(),
        'sample': sample,
      };

  factory CheckCase.fromJson(Map<String, dynamic> j) => CheckCase(
        id: j['id'],
        created: DateTime.parse(j['created']),
        community: j['community'] ?? '',
        site: j['site'] ?? '',
        buyer: j['buyer'] ?? '',
        notes: j['notes'] ?? '',
        docs: (j['docs'] as List).map((e) => CaseDoc.fromJson(e)).toList(),
        report: j['report'] as Map<String, dynamic>?,
        model: j['model'],
        checkedAt: j['checkedAt'] == null ? null : DateTime.parse(j['checkedAt']),
        sample: j['sample'] ?? false,
      );
}

/// Saves checks as folders in the app's private storage.
class CaseStore {
  static Future<Directory> root() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/checks');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<Directory> folder(CheckCase c) async {
    final d = Directory('${(await root()).path}/${c.id}');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<void> save(CheckCase c) async {
    final d = await folder(c);
    await File('${d.path}/case.json').writeAsString(jsonEncode(c.toJson()));
  }

  static Future<List<CheckCase>> all() async {
    final r = await root();
    final out = <CheckCase>[];
    await for (final e in r.list()) {
      if (e is Directory) {
        final f = File('${e.path}/case.json');
        if (await f.exists()) {
          try {
            out.add(CheckCase.fromJson(jsonDecode(await f.readAsString())));
          } catch (_) {}
        }
      }
    }
    out.sort((a, b) => b.created.compareTo(a.created));
    return out;
  }

  static Future<void> delete(CheckCase c) async {
    final d = await folder(c);
    if (await d.exists()) await d.delete(recursive: true);
  }
}
