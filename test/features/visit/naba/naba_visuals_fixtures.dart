import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uhis_next/features/visit/naba/naba_models.dart';

/// Smallest valid PNG (1×1, transparent) — the raster embedded in fixtures.
final List<int> tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

/// Server-shaped SVG wrapper around [tinyPng].
String wrappedSvg({List<int>? raster}) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024">'
    '<image width="1024" height="1024" '
    'href="data:image/png;base64,${base64Encode(raster ?? tinyPng)}"/></svg>';

String sha256Hex(String text) => sha256.convert(utf8.encode(text)).toString();

const visualImagePath = '/api/method/spice_next_ai.api.naba.visual_image?key=';

Map<String, dynamic> imageJson(String key, int order, {String? sha}) => {
  'visualKey': key,
  'order': order,
  'sha256': sha ?? sha256Hex(wrappedSvg()),
  'imagePath': '$visualImagePath$key',
};

Map<String, dynamic> visualJson({
  String en = 'Caption EN',
  String bn = 'ক্যাপশন',
  bool machine = false,
  List<Map<String, dynamic>>? images,
}) => {
  'captionEn': en,
  'captionBn': bn,
  'captionBnMachine': machine,
  'images': images ?? [imageJson('k-01', 1)],
};

/// A minimal NABA response body (already unwrapped from `message`).
NabaResponse nabaWith({
  Map<String, dynamic>? citations,
  Map<String, dynamic>? visuals,
  List<String> rationaleIds = const [],
  List<String?> findingIds = const [],
  String? referralId,
}) => NabaResponse.fromJson({
  'requestId': 'visit-1',
  'modelVersion': 'naba-spice-next-ai-1',
  'rationale': {'guidelineIds': rationaleIds},
  'visit_summary': {'summary': 's'},
  'clinical_findings': [
    for (final id in findingIds)
      {'finding': 'f', 'severity': 'info', 'guidelineId': id},
  ],
  if (referralId != null)
    'referral_recommendation': {
      'required': true,
      'urgency': 'Today',
      'guidelineId': referralId,
    },
  'citations': ?citations,
  'visuals': ?visuals,
});
