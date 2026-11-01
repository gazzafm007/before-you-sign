import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import 'models.dart';
import 'prompt.dart';
import 'settings.dart';

class AnalysisException implements Exception {
  final String message;
  AnalysisException(this.message);
  @override
  String toString() => message;
}

/// Shrinks a photo to the size Claude reads best (longest side 1568 px) and
/// saves it as a JPEG. Runs off the main thread.
Future<void> preparePhoto(String src, String dest) async {
  await compute(_prepare, [src, dest]);
}

void _prepare(List<String> a) {
  final bytes = File(a[0]).readAsBytesSync();
  var image = img.decodeImage(bytes);
  if (image == null) throw Exception('Could not read image');
  image = img.bakeOrientation(image);
  const maxSide = 1568;
  if (image.width > maxSide || image.height > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
  }
  File(a[1]).writeAsBytesSync(img.encodeJpg(image, quality: 82));
}

class Analyzer {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _maxRequestBytes = 30 * 1024 * 1024;

  http.Client? _client;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client?.close();
  }

  /// Sends the documents to Claude and returns the parsed report.
  /// [onProgress] receives the number of characters written so far.
  Future<Map<String, dynamic>> run(CheckCase c, {void Function(int chars)? onProgress}) async {
    final s = AppSettings.instance;
    if (!s.hasKey) {
      throw AnalysisException('No Claude API key has been entered. Open Settings (the gear on the home screen) and paste your key.');
    }

    final content = <Map<String, dynamic>>[];
    final labels = <String>[];
    var bytes = 0;
    var images = 0;

    for (final d in c.docs) {
      if (d.isEmpty) continue;
      var pageNo = 0;
      for (final f in d.files) {
        final data = await File(f.path).readAsBytes();
        bytes += data.length;
        if (f.isPdf) {
          content.add({'type': 'text', 'text': '=== ${d.kind.title} (PDF: ${f.name}) ==='});
          content.add({
            'type': 'document',
            'source': {'type': 'base64', 'media_type': 'application/pdf', 'data': base64Encode(data)},
            'title': '${d.kind.title} - ${f.name}',
          });
          labels.add('${d.kind.title}: PDF file ${f.name}');
        } else {
          pageNo++;
          images++;
          content.add({'type': 'text', 'text': '=== ${d.kind.title} — photographed page $pageNo ==='});
          content.add({
            'type': 'image',
            'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': base64Encode(data)},
          });
        }
      }
      if (d.photoCount > 0) labels.add('${d.kind.title}: ${d.photoCount} photographed page(s)');
    }

    if (content.isEmpty) throw AnalysisException('Please add at least one document first.');
    if (images > 100) {
      throw AnalysisException('That is $images photographed pages; the limit for one check is 100. If you have the documents as PDFs, add those instead.');
    }
    if (bytes * 4 / 3 > _maxRequestBytes) {
      throw AnalysisException('The documents are too large to send in one go (${(bytes / 1048576).toStringAsFixed(1)} MB). Try adding PDFs instead of photos, or remove duplicate pages.');
    }

    content.add({
      'type': 'text',
      'text': buildUserInstruction(
        today: DateFormat('d MMMM yyyy').format(DateTime.now()),
        community: c.community,
        site: c.site,
        buyer: c.buyer,
        notes: c.notes,
        docLabels: labels,
      ),
    });

    final body = jsonEncode({
      'model': s.model,
      'max_tokens': 32000,
      'stream': true,
      // The instructions and the standard form are the same for every check,
      // so they are cached to cut the cost of repeat checks.
      'system': [
        {
          'type': 'text',
          'text': kSystemPrompt,
          'cache_control': {'type': 'ephemeral'},
        }
      ],
      'messages': [
        {'role': 'user', 'content': content}
      ],
    });

    _cancelled = false;
    _client = http.Client();
    final req = http.Request('POST', Uri.parse(_endpoint))
      ..headers.addAll({
        'x-api-key': s.apiKey.trim(),
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      })
      ..body = body;

    final text = StringBuffer();
    try {
      final resp = await _client!.send(req).timeout(const Duration(minutes: 3));
      if (resp.statusCode != 200) {
        final err = await resp.stream.bytesToString();
        throw AnalysisException(_friendlyHttpError(resp.statusCode, err));
      }
      var buffer = '';
      String? streamError;
      await for (final chunk in resp.stream.transform(utf8.decoder).timeout(const Duration(minutes: 4))) {
        buffer += chunk;
        while (true) {
          final i = buffer.indexOf('\n');
          if (i < 0) break;
          final line = buffer.substring(0, i).trim();
          buffer = buffer.substring(i + 1);
          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload.isEmpty) continue;
          Map<String, dynamic> ev;
          try {
            ev = jsonDecode(payload);
          } catch (_) {
            continue;
          }
          final type = ev['type'];
          if (type == 'content_block_delta') {
            final delta = ev['delta'];
            if (delta is Map && delta['type'] == 'text_delta') {
              text.write(delta['text']);
              onProgress?.call(text.length);
            }
          } else if (type == 'error') {
            streamError = (ev['error']?['message'] ?? 'Unknown error').toString();
          }
        }
      }
      if (streamError != null) {
        throw AnalysisException('The checking service reported a problem: $streamError. Please try again in a few minutes.');
      }
    } on AnalysisException {
      rethrow;
    } on TimeoutException {
      throw AnalysisException('The check took too long and was stopped. Check your internet connection and try again.');
    } catch (e) {
      if (_cancelled) throw AnalysisException('Check cancelled.');
      throw AnalysisException('Could not reach the checking service. Check your internet connection and try again.\n\n($e)');
    } finally {
      _client?.close();
      _client = null;
    }

    final report = parseReport(text.toString());
    report['_prompt_version'] = kPromptVersion;
    return report;
  }

  static Map<String, dynamic> parseReport(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw AnalysisException('The report came back in an unexpected format. Please try again.');
    }
    try {
      return jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      throw AnalysisException('The report came back incomplete (it may have been too long). Please try again, or remove any documents that are not needed.');
    }
  }

  static String _friendlyHttpError(int code, String body) {
    String detail = '';
    try {
      detail = (jsonDecode(body)['error']?['message'] ?? '').toString();
    } catch (_) {}
    switch (code) {
      case 401:
        return 'The Claude API key was not accepted. Check it in Settings.';
      case 403:
        return 'This API key is not allowed to use the service ($detail).';
      case 413:
        return 'The documents are too large to send in one go. Try PDFs instead of photos, or fewer pages.';
      case 429:
        return 'Too many checks at once, or the account has run out of credit. Wait a minute and try again. ($detail)';
      case 529:
      case 503:
        return 'The checking service is busy right now. Please try again in a few minutes.';
      default:
        return 'The check could not be completed (error $code). $detail';
    }
  }
}
