import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_repository.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/patient.dart';
import '../../../core/theme/app_theme.dart';
import 'enrollment_controller.dart';
import 'nid_ocr_service.dart';
import 'patient_lookup_repository.dart';

/// Full-screen dark overlay with NID camera viewfinder.
///
/// Two states:
///   1. [_OverlayState.scanner] — camera viewfinder, sweep animation, capture
///      button, "Create Household" fallback card, Cancel.
///   2. [_OverlayState.postScan] — slide-up white sheet with scanned identity
///      card and two household linking options.
///
/// Rest of enrollment (form screens) uses GoRouter routes.
/// Shows the NID scanner overlay for adding a household member.
/// Returns the scanned [NidScanResult] when the user captures, or null on cancel.
Future<NidScanResult?> showNidScannerForMember(BuildContext context) {
  return showModalBottomSheet<NidScanResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    enableDrag: false,
    builder: (_) => const _MemberNidScanOverlay(),
  );
}

void showEnrollmentEntrySheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    enableDrag: false,
    builder: (_) => ChangeNotifierProvider(
      create: (ctx) => EnrollmentController(
        auth: ctx.read<AuthRepository>(),
        apiClient: ctx.read<ApiClient>(),
      ),
      child: const _EnrollmentOverlay(),
    ),
  );
}

enum _OverlayState { scanner, postScan }

class _EnrollmentOverlay extends StatefulWidget {
  const _EnrollmentOverlay();

  @override
  State<_EnrollmentOverlay> createState() => _EnrollmentOverlayState();
}

class _EnrollmentOverlayState extends State<_EnrollmentOverlay>
    with SingleTickerProviderStateMixin {
  _OverlayState _overlayState = _OverlayState.scanner;
  bool _isScanning = false;
  NidCardData? _scanned;

  /// A gallery-picked still shown with the scan sweep while OCR runs.
  File? _picked;

  /// Non-null when the scanned NID already belongs to a registered patient.
  Patient? _existingPatient;

  final NidOcrService _ocr = NidOcrService();

  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _cameraUnavailable = false;

  late final AnimationController _sweepCtrl;
  late final Animation<double> _sweep;

  @override
  void initState() {
    super.initState();
    debugPrint('[_EnrollmentOverlayState] initState');
    _sweepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _sweep = Tween<double>(
      begin: 0.06,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _sweepCtrl, curve: Curves.easeInOut));
    _initCamera();
  }

  /// Request camera permission and start the live preview inside the overlay.
  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() => _cameraUnavailable = true);
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraUnavailable = true);
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _cameraReady = true;
      });
    } on CameraException catch (e) {
      debugPrint('EnrollmentOverlay: camera init failed: $e');
      if (mounted) setState(() => _cameraUnavailable = true);
    }
  }

  @override
  void dispose() {
    debugPrint('[_EnrollmentOverlayState] dispose');
    _cameraController?.dispose();
    _sweepCtrl.dispose();
    super.dispose();
  }

  /// Capture a frame from the live preview and read the NID number from it.
  Future<void> _handleCapture() async {
    debugPrint('[_EnrollmentOverlayState] _handleCapture');
    final controller = _cameraController;
    if (_isScanning || controller == null || !_cameraReady) return;
    setState(() => _isScanning = true);

    NidScanResult result;
    try {
      final frame = await controller.takePicture();
      result = await _ocr.extractNidFromImage(frame.path);
    } on CameraException catch (e) {
      debugPrint('EnrollmentOverlay: takePicture failed: $e');
      result = const NidScanResult(NidScanStatus.error);
    }
    if (!mounted) return;
    setState(() => _isScanning = false);
    _onResult(result);
  }

  /// Picks a card photo from the gallery and OCRs it (offline, same pipeline as
  /// a live capture).
  Future<void> _pickFromGallery() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    NidScanResult result;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (picked == null) {
        if (mounted) setState(() => _isScanning = false);
        return; // cancelled
      }
      // Show the picked still with the scan sweep while OCR runs.
      if (mounted) setState(() => _picked = File(picked.path));
      result = await _ocr.extractNidFromImage(picked.path);
    } on Exception catch (e) {
      debugPrint('EnrollmentOverlay: gallery pick failed: $e');
      result = const NidScanResult(NidScanStatus.error);
    }
    if (!mounted) return;
    setState(() => _isScanning = false);
    _onResult(result);
  }

  /// Shared success handling for camera capture and gallery pick.
  void _onResult(NidScanResult result) {
    switch (result.status) {
      case NidScanStatus.success:
        setState(() {
          _scanned = result.data;
          _picked = null;
          _existingPatient = null;
          _overlayState = _OverlayState.postScan;
        });
        final nid = result.data?.nidNumber;
        if (nid != null) _lookupExisting(nid);
      case NidScanStatus.notFound:
      case NidScanStatus.error:
      case NidScanStatus.cancelled:
      case NidScanStatus.skipped:
        final hadPicked = _picked != null;
        setState(() => _picked = null);
        if (hadPicked) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(EnrollmentStrings.nidCouldNotReadCard)),
          );
        }
    }
  }

  /// Best-effort remote check: does this scanned NID already belong to a
  /// registered patient? Surfaces a de-duplication banner on the post-scan
  /// sheet. Offline / transport failures degrade silently.
  Future<void> _lookupExisting(String nid) async {
    final repo = context.read<PatientLookupRepository>();
    try {
      final patient = await repo.lookupByNid(nid);
      if (!mounted || patient == null) return;
      setState(() => _existingPatient = patient);
    } on DioException catch (_) {
      // Offline or transport error — no duplicate warning, no user-facing error.
    } on ApiException catch (e) {
      debugPrint('EnrollmentOverlay: patient lookup failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return SizedBox(
      height: screenH,
      child: Material(
        color: Colors.black.withValues(alpha: 0.92),
        child: SafeArea(
          child: Stack(
            children: [
              _ScannerBody(
                isScanning: _isScanning,
                sweep: _sweep,
                readingCard: _overlayState == _OverlayState.postScan,
                cameraController: _cameraReady ? _cameraController : null,
                cameraUnavailable: _cameraUnavailable,
                previewImage: _picked,
                onCapture: _handleCapture,
                onPickFromGallery: _pickFromGallery,
                onCreateHousehold: () {
                  Navigator.of(context).pop();
                  context.push('/household/enrollment/create');
                },
                onCancel: () => Navigator.of(context).pop(),
                onRegisterManually: () {
                  Navigator.of(context).pop();
                  context.push('/household/enrollment/select-household');
                },
              ),
              if (_overlayState == _OverlayState.postScan)
                _PostScanSheet(
                  data: _scanned,
                  existing: _existingPatient,
                  onLinkExisting: () {
                    Navigator.of(context).pop();
                    context.push(
                      '/household/enrollment/select-household',
                      extra: {
                        'fromNidScan': true,
                        'nidNumber': _scanned?.nidNumber,
                        'name': _scanned?.name,
                        'dateOfBirth': _scanned?.dateOfBirth,
                      },
                    );
                  },
                  onCreateNew: () {
                    Navigator.of(context).pop();
                    context.push(
                      '/household/enrollment/create',
                      extra: {
                        'fromNidScan': true,
                        'nidNumber': _scanned?.nidNumber,
                        'name': _scanned?.name,
                        'dateOfBirth': _scanned?.dateOfBirth,
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Member NID scan overlay ──────────────────────────────────────────────────

/// Simplified NID scanner overlay used when adding a household member.
/// On capture success, pops with [NidScanResult]; cancel pops with null.
class _MemberNidScanOverlay extends StatefulWidget {
  const _MemberNidScanOverlay();

  @override
  State<_MemberNidScanOverlay> createState() => _MemberNidScanOverlayState();
}

class _MemberNidScanOverlayState extends State<_MemberNidScanOverlay>
    with SingleTickerProviderStateMixin {
  bool _isScanning = false;
  final NidOcrService _ocr = NidOcrService();
  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _cameraUnavailable = false;

  /// Non-null once a card has been read — drives the editable review step.
  NidCardData? _scanned;

  /// A gallery-picked still shown with the scan sweep while OCR runs.
  File? _picked;
  final TextEditingController _nameCtrl = TextEditingController();

  /// Selected gender in the review step — one of [EnrollmentStrings.gendersMember]
  /// first two entries ('Male' / 'Female'), or null until the SK picks.
  String? _reviewGender;

  late final AnimationController _sweepCtrl;
  late final Animation<double> _sweep;

  @override
  void initState() {
    super.initState();
    debugPrint('[_MemberNidScanOverlayState] initState');
    _sweepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _sweep = Tween<double>(begin: 0.06, end: 0.92).animate(
      CurvedAnimation(parent: _sweepCtrl, curve: Curves.easeInOut),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() => _cameraUnavailable = true);
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraUnavailable = true);
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _cameraReady = true;
      });
    } on CameraException catch (e) {
      debugPrint('MemberNidScan: camera init failed: $e');
      if (mounted) setState(() => _cameraUnavailable = true);
    }
  }

  @override
  void dispose() {
    debugPrint('[_MemberNidScanOverlayState] dispose');
    _cameraController?.dispose();
    _nameCtrl.dispose();
    _sweepCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleCapture() async {
    debugPrint('[_MemberNidScanOverlayState] _handleCapture');
    final controller = _cameraController;
    if (_isScanning || controller == null || !_cameraReady) return;
    setState(() => _isScanning = true);
    NidScanResult result;
    try {
      final frame = await controller.takePicture();
      result = await _ocr.extractNidFromImage(frame.path);
    } on CameraException catch (e) {
      debugPrint('MemberNidScan: takePicture failed: $e');
      result = const NidScanResult(NidScanStatus.error);
    }
    if (!mounted) return;
    setState(() => _isScanning = false);
    _onResult(result);
  }

  /// Picks a card photo from the gallery and OCRs it (offline, same pipeline as
  /// a live capture) — for SKs who photographed the card earlier or received it
  /// over a messaging app.
  Future<void> _pickFromGallery() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    NidScanResult result;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (picked == null) {
        if (mounted) setState(() => _isScanning = false);
        return; // cancelled
      }
      // Show the picked still with the scan sweep while OCR runs.
      if (mounted) setState(() => _picked = File(picked.path));
      result = await _ocr.extractNidFromImage(picked.path);
    } on Exception catch (e) {
      debugPrint('MemberNidScan: gallery pick failed: $e');
      result = const NidScanResult(NidScanStatus.error);
    }
    if (!mounted) return;
    setState(() => _isScanning = false);
    _onResult(result);
  }

  /// Shared success handling for both camera capture and gallery pick: enter the
  /// editable review step instead of applying OCR blindly.
  void _onResult(NidScanResult result) {
    switch (result.status) {
      case NidScanStatus.success:
        final data = result.data!;
        setState(() {
          _scanned = data;
          _picked = null;
          _nameCtrl.text = data.name ?? '';
          _reviewGender = data.gender?.label;
          _cameraController?.dispose();
          _cameraController = null;
          _cameraReady = false;
        });
      case NidScanStatus.notFound:
      case NidScanStatus.error:
      case NidScanStatus.cancelled:
      case NidScanStatus.skipped:
        // Clear the preview and tell the SK the read failed (esp. for gallery,
        // which has no auto-retry). Live camera stays up to try again.
        final hadPicked = _picked != null;
        setState(() => _picked = null);
        if (hadPicked) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(EnrollmentStrings.nidCouldNotReadCard)),
          );
        }
    }
  }

  /// Confirms the reviewed fields and pops the (possibly SK-corrected) data.
  void _confirmReview() {
    final base = _scanned;
    if (base == null) return;
    final name = _nameCtrl.text.trim();
    final gender = _reviewGender == 'Male'
        ? NidGender.male
        : _reviewGender == 'Female'
            ? NidGender.female
            : null;
    Navigator.of(context).pop(
      NidScanResult(
        NidScanStatus.success,
        NidCardData(
          nidNumber: base.nidNumber,
          name: name.isEmpty ? null : name,
          dateOfBirth: base.dateOfBirth,
          gender: gender,
        ),
      ),
    );
  }

  /// Returns to the live scanner to try another capture.
  void _rescan() {
    setState(() {
      _scanned = null;
      _picked = null;
      _nameCtrl.clear();
      _reviewGender = null;
    });
    _initCamera();
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return SizedBox(
      height: screenH,
      child: Material(
        color: Colors.black.withValues(alpha: 0.92),
        child: SafeArea(
          child: Stack(
            children: [
              _ScannerBody(
                isScanning: _isScanning,
                sweep: _sweep,
                readingCard: _scanned != null,
                cameraController: _cameraReady ? _cameraController : null,
                cameraUnavailable: _cameraUnavailable,
                previewImage: _picked,
                onCapture: _handleCapture,
                onPickFromGallery: _pickFromGallery,
                onCreateHousehold: () {},
                onCancel: () => Navigator.of(context).pop(null),
                showCreateHousehold: false,
                onRegisterManually: () => Navigator.of(context)
                    .pop(const NidScanResult(NidScanStatus.skipped)),
              ),
              if (_scanned != null)
                _MemberReviewSheet(
                  data: _scanned!,
                  nameController: _nameCtrl,
                  gender: _reviewGender,
                  onGenderChanged: (g) => setState(() => _reviewGender = g),
                  onConfirm: _confirmReview,
                  onRescan: _rescan,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Member scan review sheet (editable "what we found") ──────────────────────

/// Slide-up sheet shown after a member NID scan: the fields OCR read, made
/// **editable** so the SK corrects the name (guards against a misread name
/// landing silently) and picks the gender (which the Latin front rarely
/// prints). Confirm pops the reviewed data; Rescan returns to the camera.
class _MemberReviewSheet extends StatelessWidget {
  const _MemberReviewSheet({
    required this.data,
    required this.nameController,
    required this.gender,
    required this.onGenderChanged,
    required this.onConfirm,
    required this.onRescan,
  });

  final NidCardData data;
  final TextEditingController nameController;
  final String? gender;
  final ValueChanged<String?> onGenderChanged;
  final VoidCallback onConfirm;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final dob = data.dateOfBirth;
    final nid = data.nidNumber;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(color: Color(0x2E000000), blurRadius: 32, offset: Offset(0, -8)),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.h5xl,
          AppSpacing.xxxl,
          AppSpacing.h5xl,
          AppSpacing.h8xl,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                EnrollmentStrings.nidReviewTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                EnrollmentStrings.nidReviewSubtitle,
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              // Editable name.
              Text(
                EnrollmentStrings.nidReviewNameLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: EnrollmentStrings.nidReviewNameHint,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.field),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Gender selector.
              Text(
                EnrollmentStrings.genderLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final g in const ['Male', 'Female']) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => onGenderChanged(g),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: gender == g
                                ? AppColors.navy
                                : Colors.white,
                            border: Border.all(
                              color: gender == g
                                  ? AppColors.navy
                                  : AppColors.border,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.field),
                          ),
                          child: Center(
                            child: Text(
                              g,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: gender == g
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (g == 'Male') const SizedBox(width: 10),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                EnrollmentStrings.nidReviewGenderHint,
                style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
              ),
              const SizedBox(height: 14),
              // Read-only DOB + NID summary.
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.navy, AppColors.navyMid],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.patRow),
                ),
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _NidField(
                      label: EnrollmentStrings.nidFieldDobLabel,
                      value: dob ?? EnrollmentStrings.nidFieldNotReadValue,
                      dim: dob == null,
                    ),
                    const _NidDivider(),
                    _NidField(
                      label: EnrollmentStrings.nidFieldNidLabel,
                      value: nid ?? '—',
                      emphasise: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Confirm.
              GestureDetector(
                onTap: onConfirm,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  child: Center(
                    child: Text(
                      EnrollmentStrings.nidReviewConfirm,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Rescan.
              GestureDetector(
                onTap: onRescan,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.border, width: 1.5),
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.replay, size: 16, color: AppColors.navy),
                        const SizedBox(width: 6),
                        Text(
                          EnrollmentStrings.nidReviewRescan,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Scanner body ─────────────────────────────────────────────────────────────

class _ScannerBody extends StatelessWidget {
  const _ScannerBody({
    required this.isScanning,
    required this.sweep,
    required this.readingCard,
    required this.cameraController,
    required this.cameraUnavailable,
    required this.onCapture,
    required this.onCreateHousehold,
    required this.onCancel,
    this.showCreateHousehold = true,
    this.onLinkToExisting,
    this.onRegisterManually,
    this.onPickFromGallery,
    this.previewImage,
  });

  final bool isScanning;
  final bool readingCard;
  final Animation<double> sweep;

  /// Live preview controller, or null while initialising / unavailable.
  final CameraController? cameraController;
  final bool cameraUnavailable;

  /// A picked still to show (instead of the live camera) while OCR runs.
  final File? previewImage;
  final VoidCallback onCapture;
  final VoidCallback onCreateHousehold;
  final VoidCallback onCancel;
  /// When false, hides the "Create Household" card and "or" divider.
  final bool showCreateHousehold;
  /// Optional: navigates to SelectHouseholdScreen.
  final VoidCallback? onLinkToExisting;
  /// Optional: skips NID scan and opens manual registration form.
  final VoidCallback? onRegisterManually;
  /// Optional: picks a card photo from the gallery instead of the live camera.
  final VoidCallback? onPickFromGallery;

  bool get _canCapture =>
      !isScanning && !readingCard && cameraController != null;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.max,
      children: [
          // ── Create Household (primary) ─────────────────────────────────
          if (showCreateHousehold) ...[
          GestureDetector(
            onTap: onCreateHousehold,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(AppRadius.patRow),
              ),
              child: Row(
                children: [
                  const Icon(Icons.home_outlined, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          EnrollmentStrings.createHousehold,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          EnrollmentStrings.entrySheetCreateHouseholdSubtitle,
                          style: const TextStyle(fontSize: 10, color: AppColors.onDarkLow),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.onDarkFaint, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ── Link to Existing Household ─────────────────────────────────────
          if (onLinkToExisting != null)
            GestureDetector(
              onTap: onLinkToExisting,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.20),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.patRow),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            EnrollmentStrings.entrySheetLinkExistingTitle,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            EnrollmentStrings.entrySheetLinkExistingSubtitle,
                            style: const TextStyle(fontSize: 10, color: AppColors.onDarkLow),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.onDarkFaint, size: 16),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          // Or divider
          Row(
            children: [
              Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.15))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(CommonStrings.or, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.onDarkFaint)),
              ),
              Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.15))),
            ],
          ),
          const SizedBox(height: 14),
          ], // end if (showCreateHousehold)
          // ── Register without NID (primary escape hatch) ───────────────
          if (onRegisterManually != null) ...[
            GestureDetector(
              onTap: onRegisterManually,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.20), width: 1.5),
                  borderRadius: BorderRadius.circular(AppRadius.patRow),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_add_outlined, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            EnrollmentStrings.entrySheetRegisterManuallyTitle,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            EnrollmentStrings.entrySheetRegisterManuallySubtitle,
                            style: const TextStyle(fontSize: 10, color: AppColors.onDarkLow),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.onDarkFaint, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.15))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(EnrollmentStrings.orScanNid, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.onDarkFaint)),
                ),
                Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.15))),
              ],
            ),
            const SizedBox(height: 14),
          ],
          // ── Camera scanner (secondary) ─────────────────────────────────
          Text(
            readingCard
                ? EnrollmentStrings.nidReadingCardDetailsHeadline
                : EnrollmentStrings.nidTakePhotoHeadline,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            readingCard
                ? EnrollmentStrings.nidReadingNumberSubtitle
                : cameraUnavailable
                ? EnrollmentStrings.cameraUnavailableLabel
                : EnrollmentStrings.positionCardSubtitle,
            style: const TextStyle(fontSize: 12, color: AppColors.onDarkLow),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _Viewfinder(
              isScanning: isScanning,
              sweep: sweep,
              cameraController: cameraController,
              cameraUnavailable: cameraUnavailable,
              previewImage: previewImage,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            EnrollmentStrings.nidScanCardTypesCaption,
            style: const TextStyle(fontSize: 11, color: AppColors.onDarkFaint),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          // Capture button (centre) + gallery upload (left).
          SizedBox(
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                GestureDetector(
                  onTap: _canCapture ? onCapture : null,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 4),
                    ),
                    child: Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                            color: _canCapture ? AppColors.textPrimary : Colors.grey,
                            width: 2,
                          ),
                        ),
                        child: (isScanning || readingCard)
                            ? const Padding(
                                padding: EdgeInsets.all(AppSpacing.xxxl),
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary),
                              )
                            : const Icon(Icons.camera_alt, color: AppColors.textPrimary, size: 24),
                      ),
                    ),
                  ),
                ),
                if (onPickFromGallery != null)
                  Positioned(
                    left: 24,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: (isScanning || readingCard) ? null : onPickFromGallery,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(Icons.photo_library_outlined,
                                color: Colors.white, size: 22),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          EnrollmentStrings.nidUploadLabel,
                          style: const TextStyle(fontSize: 10, color: AppColors.onDarkFaint),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(EnrollmentStrings.tapToCapture, style: const TextStyle(fontSize: 11, color: AppColors.onDarkFaint)),
          const SizedBox(height: 20),
          // Cancel
          GestureDetector(
            onTap: onCancel,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.h7xl,
                vertical: AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                borderRadius: BorderRadius.circular(AppRadius.field),
              ),
              child: Text(
                EnrollmentStrings.cancel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );

    final screenH = MediaQuery.of(context).size.height;
    return SizedBox(
      height: screenH,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.h5xl,
          AppSpacing.h5xl,
          AppSpacing.h5xl,
          AppSpacing.h6xl,
        ),
        child: content,
      ),
    );
  }
}

// ─── Viewfinder ───────────────────────────────────────────────────────────────

class _Viewfinder extends StatelessWidget {
  const _Viewfinder({
    required this.isScanning,
    required this.sweep,
    required this.cameraController,
    required this.cameraUnavailable,
    this.previewImage,
  });

  final bool isScanning;
  final Animation<double> sweep;
  final CameraController? cameraController;
  final bool cameraUnavailable;

  /// A picked/captured still shown (instead of the live camera) while OCR runs.
  final File? previewImage;

  static const double _inset = 10;
  static const double _cSize = 28;
  static const double _cThick = 3;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = w / 1.586; // credit-card landscape ratio
        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            children: [
              // Live camera preview (cover-fit into the card rect) or a
              // translucent placeholder while the camera initialises.
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: previewImage != null
                      ? Image.file(previewImage!, fit: BoxFit.cover)
                      : cameraController != null
                          ? FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox(
                                width:
                                    cameraController!.value.previewSize?.height ??
                                    w,
                                height:
                                    cameraController!.value.previewSize?.width ??
                                    h,
                                child: CameraPreview(cameraController!),
                              ),
                            )
                          : Container(color: Colors.white.withValues(alpha: 0.04)),
                ),
              ),
              // Inner dashed hint
              Positioned(
                left: 20,
                right: 20,
                top: 20,
                bottom: 20,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.field),
                  ),
                  child: (isScanning || cameraController != null)
                      ? null
                      : Center(
                          child: Icon(
                            cameraUnavailable
                                ? Icons.no_photography_outlined
                                : Icons.credit_card_outlined,
                            color: AppColors.onDarkSurface,
                            size: 40,
                          ),
                        ),
                ),
              ),
              // Corner brackets
              _corner(top: _inset, left: _inset),
              _corner(top: _inset, left: w - _inset - _cSize, flipH: true),
              _corner(top: h - _inset - _cSize, left: _inset, flipV: true),
              _corner(
                top: h - _inset - _cSize,
                left: w - _inset - _cSize,
                flipH: true,
                flipV: true,
              ),
              // Sweep line — also runs over a still preview while OCR is busy.
              if (!isScanning || previewImage != null)
                AnimatedBuilder(
                  animation: sweep,
                  builder: (context2, value) => Positioned(
                    top: sweep.value * h,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 2,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            AppColors.tbBorder,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Scanning spinner
              if (isScanning)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: AppColors.tbBorder,
                        strokeWidth: 2.5,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        EnrollmentStrings.nidScanningLabel,
                        style: const TextStyle(
                          color: AppColors.onDarkMid,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static Widget _corner({
    required double top,
    required double left,
    bool flipH = false,
    bool flipV = false,
  }) {
    return Positioned(
      top: top,
      left: left,
      child: SizedBox(
        width: _cSize,
        height: _cSize,
        child: CustomPaint(
          painter: _CornerPainter(flipH: flipH, flipV: flipV, thick: _cThick),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({
    required this.flipH,
    required this.flipV,
    required this.thick,
  });

  final bool flipH, flipV;
  final double thick;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.tbBorder
      ..strokeWidth = thick
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final x = flipH ? size.width : 0.0;
    final y = flipV ? size.height : 0.0;
    final xEnd = flipH ? 0.0 : size.width;
    final yEnd = flipV ? 0.0 : size.height;

    canvas.drawLine(Offset(x, y), Offset(xEnd, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, yEnd), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

// ─── Post-scan bottom sheet ───────────────────────────────────────────────────

class _PostScanSheet extends StatelessWidget {
  const _PostScanSheet({
    required this.data,
    required this.existing,
    required this.onLinkExisting,
    required this.onCreateNew,
  });

  final NidCardData? data;

  /// Non-null when the scanned NID matches a patient already registered.
  final Patient? existing;
  final VoidCallback onLinkExisting;
  final VoidCallback onCreateNew;

  @override
  Widget build(BuildContext context) {
    final name = data?.name;
    final dob = data?.dateOfBirth;
    final nid = data?.nidNumber;
    final existingName = existing?.name;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Color(0x2E000000),
              blurRadius: 32,
              offset: Offset(0, -8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.h5xl,
          AppSpacing.xxxl,
          AppSpacing.h5xl,
          AppSpacing.h8xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        EnrollmentStrings.postScanSheetTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        EnrollmentStrings.detailsReadOnDeviceLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Navy gradient card with the auto-filled fields
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.navy, AppColors.navyMid],
                ),
                borderRadius: BorderRadius.circular(AppRadius.patRow),
              ),
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NidField(
                    label: EnrollmentStrings.nidFieldNameLabel,
                    value: name ?? EnrollmentStrings.nidFieldNotReadValue,
                    dim: name == null,
                  ),
                  const _NidDivider(),
                  _NidField(
                    label: EnrollmentStrings.nidFieldDobLabel,
                    value: dob ?? EnrollmentStrings.nidFieldNotReadValue,
                    dim: dob == null,
                  ),
                  const _NidDivider(),
                  _NidField(
                    label: EnrollmentStrings.nidFieldNidLabel,
                    value: nid ?? '—',
                    emphasise: true,
                  ),
                ],
              ),
            ),
            // Existing-registration de-duplication banner
            if (existing != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.lg,
                ),
                decoration: BoxDecoration(
                  color: AppColors.childSurface,
                  border: Border.all(color: AppColors.infoAccent),
                  borderRadius: BorderRadius.circular(AppRadius.field),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.badge_outlined,
                      size: 16,
                      color: AppColors.infoAccentDark,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            EnrollmentStrings.existingPatientFound(
                              existingName ?? '',
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.infoAccentDark,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            EnrollmentStrings.existingPatientHint,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.infoAccentDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Father / Mother cannot be OCR'd (Bengali only) — set expectation.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: AppColors.ncdSurface,
                border: Border.all(color: AppColors.warningBorderAlt),
                borderRadius: BorderRadius.circular(AppRadius.field),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 15,
                    color: AppColors.warningTextAlt,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      EnrollmentStrings.banglaNamesHint,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.warningTextAlt,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                EnrollmentStrings.linkToHouseholdLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _SheetOptionButton(
              icon: Icons.link_rounded,
              title: EnrollmentStrings.postScanLinkOptionTitle,
              subtitle: EnrollmentStrings.postScanLinkOptionSubtitle,
              bgColor: AppColors.cardSurfaceMuted,
              onTap: onLinkExisting,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(child: Divider(color: AppColors.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    CommonStrings.or,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDisabled,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: AppColors.border)),
              ],
            ),
            const SizedBox(height: 10),
            _SheetOptionButton(
              icon: Icons.home_outlined,
              title: EnrollmentStrings.postScanCreateOptionTitle,
              subtitle: EnrollmentStrings.postScanCreateOptionSubtitle,
              bgColor: Colors.white,
              bordered: true,
              onTap: onCreateNew,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetOptionButton extends StatelessWidget {
  const _SheetOptionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bgColor,
    required this.onTap,
    this.bordered = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color bgColor;
  final VoidCallback onTap;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(
            color: bordered ? AppColors.navy : AppColors.border,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.navy, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textDisabled,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// One label/value row inside the navy scanned-details card.
class _NidField extends StatelessWidget {
  const _NidField({
    required this.label,
    required this.value,
    this.emphasise = false,
    this.dim = false,
  });

  final String label;
  final String value;
  final bool emphasise;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.onDarkFaint,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasise ? 20 : 14,
            fontWeight: emphasise ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: emphasise ? 1.5 : 0,
            fontStyle: dim ? FontStyle.italic : FontStyle.normal,
            color: dim ? AppColors.onDarkFaint : Colors.white,
          ),
        ),
      ],
    );
  }
}

class _NidDivider extends StatelessWidget {
  const _NidDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      color: Colors.white.withValues(alpha: 0.12),
    );
  }
}
