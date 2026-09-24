/// A button that fetches a completed call's prescription/invoice bytes live,
/// on tap -- never eagerly, never cached -- then opens the full document in
/// [PdfViewerScreen]. Used by [TeleconsultCallDetailScreen] for historical
/// calls synced in from Frappe: unlike `_DocumentPreviewCard` (the live-call
/// wrap-up view, which eagerly prefetches because the SK is looking at it
/// right after the call ends), a historical call's documents are fetched
/// only if and when the user actually asks to see them, since bulk-fetching
/// every synced call's PDFs would be an unbounded, unpredictable cost.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shukhee_sdk/shukhee_sdk.dart';

import '../../core/constants/app_strings.dart';
import 'pdf_viewer_screen.dart';

class DocumentDownloadButton extends StatefulWidget {
  const DocumentDownloadButton({
    super.key,
    required this.client,
    required this.callLog,
    required this.docType,
    required this.title,
    required this.buttonLabel,
    required this.icon,
  });

  final ShukheeClient client;
  final String callLog;
  final String docType;
  final String title;
  final String buttonLabel;
  final IconData icon;

  @override
  State<DocumentDownloadButton> createState() => _DocumentDownloadButtonState();
}

class _DocumentDownloadButtonState extends State<DocumentDownloadButton> {
  bool _loading = false;

  Future<void> _download() async {
    setState(() => _loading = true);
    try {
      final result = await widget.client.downloadDocument(
        callLog: widget.callLog,
        docType: widget.docType,
      );
      final bytes = Uint8List.fromList(result.bytes);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PdfViewerScreen(title: widget.title, bytes: bytes),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(TeleconsultStrings.documentOpenFailed)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _loading ? null : _download,
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(widget.icon, size: 18),
      label: Text(widget.buttonLabel),
    );
  }
}
