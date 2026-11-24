// Writes the checking instructions to the server folder, so the server runs
// the same prompt as the app. Run after changing lib/prompt.dart:
//   dart run tool/export_prompt.dart
// then upload server/bys/prompt/ to the hosting.
import 'dart:io';

import 'package:before_you_sign/prompt.dart';

void main() {
  final dir = Directory('server/bys/prompt')..createSync(recursive: true);
  File('${dir.path}/system.txt').writeAsStringSync(kSystemPrompt);
  File('${dir.path}/version.txt').writeAsStringSync('$kPromptVersion\n');
  stdout.writeln('Wrote ${dir.path}/system.txt (${kSystemPrompt.length} characters, prompt $kPromptVersion)');
}
