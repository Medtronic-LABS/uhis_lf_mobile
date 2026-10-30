/// In-app fullscreen multi-page PDF viewer.
///
/// Used by the teleconsult wrap-up screen to show a completed consultation's
/// prescription/invoice without ever handing the document to an external
/// app — the SK stays inside Leapwell the whole time.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../core/theme/app_theme.dart';

class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({super.key, required this.title, required this.bytes});

  final String title;
  final Uint8List bytes;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late final PdfControllerPinch _controller = PdfControllerPinch(
    document: PdfDocument.openData(widget.bytes),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppColors.ancHeader,
        foregroundColor: Colors.white,
      ),
      body: PdfViewPinch(controller: _controller),
    );
  }
}
