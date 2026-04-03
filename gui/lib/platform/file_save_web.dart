// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:typed_data';
import 'dart:html' as html;

import 'file_save.dart';
import 'file_names.dart';

Future<SavedFileResult> saveEdfBytes({
  required Uint8List bytes,
  required String suggestedBaseName,
  required String filenameSuffix,
  required String datasetPath,
  required String outputDirectory,
}) async {
  final String filename =
      '${sanitizeFilename(suggestedBaseName.isEmpty ? 'brainstory_signal' : suggestedBaseName)}$filenameSuffix.edf';
  final html.Blob blob = html.Blob(<dynamic>[bytes], 'application/octet-stream');
  final String url = html.Url.createObjectUrlFromBlob(blob);
  final html.AnchorElement anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return SavedFileResult(
    locationLabel: filename,
    persistedToDisk: false,
  );
}

Future<SavedFileResult> saveTextFile({
  required String text,
  required String suggestedBaseName,
  required String filenameSuffix,
  required String fileExtension,
  required String datasetPath,
  required String outputDirectory,
}) async {
  final String extension =
      fileExtension.startsWith('.') ? fileExtension.substring(1) : fileExtension;
  final String filename =
      '${sanitizeFilename(suggestedBaseName.isEmpty ? 'brainstory_export' : suggestedBaseName)}$filenameSuffix.$extension';
  final html.Blob blob = html.Blob(<dynamic>[text], 'text/plain');
  final String url = html.Url.createObjectUrlFromBlob(blob);
  final html.AnchorElement anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return SavedFileResult(
    locationLabel: filename,
    persistedToDisk: false,
  );
}
