// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'file_names.dart';

Future<String?> saveBrainStoryProject({
  required String suggestedName,
  required String jsonPayload,
  String? targetPath,
}) async {
  final String filename =
      '${sanitizeFilename(suggestedName.isEmpty ? 'brainstory_project' : suggestedName)}.bst';
  final html.Blob blob =
      html.Blob(<Object>[jsonPayload], 'application/json');
  final String url = html.Url.createObjectUrlFromBlob(blob);
  final html.AnchorElement anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return filename;
}
