/// Every place `lib/` opens an HTTP or WebSocket transport, and how the
/// network log covers it. Compared with a source scan by
/// `transport_registry_test.dart`; see spec section 7a for the inventory.
library;

/// How a transport reaches the network log.
enum CoverageKind {
  /// Built inside the `ApiClient.create()` interceptor chain.
  apiClientChain('attachNetworkLog('),

  /// Gets the log through `attachAiServiceAuth`, which attaches it.
  aiServiceAuth('attachAiServiceAuth('),

  /// Calls `ApiClient.attachNetworkLog` itself.
  attachNetworkLog('attachNetworkLog('),

  /// Takes a recorder and attaches `NetworkLogInterceptor` to its own Dio.
  recorderParam('recorder'),

  /// WebSocket seam that records the handshake.
  wsSeam('recorder'),

  /// A helper object owned by a transport that is itself covered.
  coveredByOwner('attachNetworkLog('),

  /// Imported but makes no request.
  inert('package:http/');

  const CoverageKind(this.evidenceToken);

  /// Text the registered file must contain as proof of coverage.
  final String evidenceToken;
}

class TransportEntry {
  const TransportEntry(
    this.file,
    this.pattern,
    this.count,
    this.kind,
    this.reason, {
    this.evidenceFile,
    this.evidenceToken,
    this.extraEvidence = const [],
    this.minEvidence = 1,
  });

  final String file;

  /// One of the patterns in [transportPatterns].
  final String pattern;
  final int count;
  final CoverageKind kind;
  final String reason;

  /// File holding the evidence when it is not [file] itself.
  final String? evidenceFile;

  /// Overrides the kind's default token.
  final String? evidenceToken;

  /// Further tokens that must also be present (a file with two Dios).
  final List<String> extraEvidence;

  /// How many times the evidence token must appear (comment-stripped).
  final int minEvidence;

  String get key => '$file | $pattern';
}

const _dio = r'\bDio\s*\(';
const _httpClient = r'HttpClient\(\)';
const _ioWs = 'IOWebSocketChannel';
const _wsConnect = r'WebSocketChannel\.connect';
const _pkgHttp = 'package:http/';
const _shukheeClient = r'(?<![A-Za-z0-9_])ShukheeClient\(';

/// Source patterns that identify a transport.
const transportPatterns = <String>[
  _dio,
  _ioWs,
  _wsConnect,
  _httpClient,
  _pkgHttp,
  r'http\.(get|post|put|delete|Client|Request)\(',
  _shukheeClient,
];

const transportRegistry = <TransportEntry>[
  TransportEntry(
    'lib/core/api/api_client.dart',
    _dio,
    1,
    CoverageKind.apiClientChain,
    'main Dio; create() attaches the log',
    evidenceToken: 'client.attachNetworkLog(',
  ),
  TransportEntry(
    'lib/core/api/api_client.dart',
    _httpClient,
    1,
    CoverageKind.coveredByOwner,
    'debug cert-bypass adapter of the main Dio',
    evidenceToken: 'client.attachNetworkLog(',
  ),
  TransportEntry(
    'lib/core/api/frappe_client.dart',
    _dio,
    1,
    CoverageKind.recorderParam,
    'FrappeClient default Dio',
    evidenceToken: 'networkRecorder',
  ),
  TransportEntry(
    'lib/core/api/scribe_api_service.dart',
    _dio,
    1,
    CoverageKind.attachNetworkLog,
    'scribe Dio',
  ),
  TransportEntry(
    'lib/core/auth/user_hierarchy_service.dart',
    _dio,
    2,
    CoverageKind.attachNetworkLog,
    'feature-flag and Shukhee kill-switch one-shot Dios',
    evidenceToken: '_prepareOneShotDio(tempDio)',
    extraEvidence: ['_api.attachNetworkLog('],
    minEvidence: 2,
  ),
  TransportEntry(
    'lib/core/sync/call_log_sync_client.dart',
    _dio,
    1,
    CoverageKind.recorderParam,
    'call log sync Dio',
    evidenceToken: 'networkRecorder',
  ),
  TransportEntry(
    'lib/core/sync/shukhee_encounter_link_client.dart',
    _dio,
    1,
    CoverageKind.recorderParam,
    'encounter link Dio',
    evidenceToken: 'networkRecorder',
  ),
  TransportEntry(
    'lib/core/telemetry/telemetry_uploader.dart',
    _dio,
    1,
    CoverageKind.aiServiceAuth,
    'direct AI Dio',
  ),
  TransportEntry(
    'lib/core/telemetry/assistant_content_uploader.dart',
    _dio,
    1,
    CoverageKind.aiServiceAuth,
    'direct AI Dio',
  ),
  TransportEntry(
    'lib/core/telemetry/value_audit_uploader.dart',
    _dio,
    1,
    CoverageKind.aiServiceAuth,
    'direct AI Dio',
  ),
  TransportEntry(
    'lib/core/telemetry/visit_content_uploader.dart',
    _dio,
    1,
    CoverageKind.aiServiceAuth,
    'direct AI Dio',
  ),
  TransportEntry(
    'lib/core/version/app_version_service.dart',
    _dio,
    1,
    CoverageKind.aiServiceAuth,
    'app-version check Dio',
  ),
  TransportEntry(
    'lib/features/assistant/assistant_repository.dart',
    _dio,
    2,
    CoverageKind.attachNetworkLog,
    'direct AI Dio plus coaching RAG Dio',
    extraEvidence: ['attachAiServiceAuth('],
  ),
  TransportEntry(
    'lib/features/visit/briefing/visit_briefing_repository.dart',
    _dio,
    1,
    CoverageKind.aiServiceAuth,
    'briefing direct Dio',
  ),
  TransportEntry(
    'lib/features/visit/immunisation/card_extraction_transport.dart',
    _dio,
    1,
    CoverageKind.aiServiceAuth,
    'card OCR direct Dio',
  ),
  TransportEntry(
    'lib/features/teleconsult/shukhee_consent_client.dart',
    _dio,
    1,
    CoverageKind.recorderParam,
    'consent Dio',
    evidenceToken: 'networkRecorder',
  ),
  TransportEntry(
    'lib/features/teleconsult/shukhee_client_factory.dart',
    _dio,
    1,
    CoverageKind.recorderParam,
    'Dio injected into ShukheeClient; recorder comes from this factory',
    evidenceToken: 'recorder ?? apiClient.networkRecorder',
  ),
  TransportEntry(
    'lib/features/teleconsult/shukhee_client_factory.dart',
    _shukheeClient,
    1,
    CoverageKind.recorderParam,
    'the one app ShukheeClient; built with the logged Dio',
    evidenceToken: 'recorder ?? apiClient.networkRecorder',
  ),
  TransportEntry(
    'lib/features/realtime_asr/realtime_asr_channel_io.dart',
    _ioWs,
    1,
    CoverageKind.wsSeam,
    'native realtime ASR WebSocket',
    evidenceToken: 'recorder.record(',
  ),
  TransportEntry(
    'lib/features/realtime_asr/realtime_asr_channel_io.dart',
    _wsConnect,
    1,
    CoverageKind.wsSeam,
    'same call as IOWebSocketChannel',
    evidenceToken: 'recorder.record(',
  ),
  TransportEntry(
    'lib/features/realtime_asr/realtime_asr_channel_io.dart',
    _httpClient,
    1,
    CoverageKind.coveredByOwner,
    'debug WS client; covered by the WebSocket seam',
    evidenceToken: 'recorder.record(',
  ),
  TransportEntry(
    'lib/features/visit/eval/eval_fhir_uploader.dart',
    _pkgHttp,
    1,
    CoverageKind.inert,
    'import for http.ClientException only; no request is made',
  ),
];
