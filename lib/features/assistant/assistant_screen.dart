library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/i18n/app_locale.dart';
import '../../core/services/micro_coaching_service.dart';

/// Assistant tab — launches CoachingFlowActivity (MicroCoaching SDK).
/// Bottom nav intercepts the tab tap and calls SDK directly; this screen
/// acts as a fallback for /assistant deep-links or direct navigation.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  bool _launching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _launch();
  }

  Future<void> _launch() async {
    if (_launching) return;
    setState(() { _launching = true; _error = null; });
    try {
      final repo = context.read<AuthRepository>();
      final userId = await repo.userId();
      final chwId = userId?.toString() ?? 'chw_unknown';
      if (!await MicroCoachingService.isInitialized()) {
        final token = await repo.getToken();
        if (token == null || token.isEmpty) throw Exception('No auth token');
        await MicroCoachingService.initialize(
          authToken: token,
          backendUrl: AppConfig.coachingServiceUrl,
          language: AppLocale.isBangla ? 'bn' : 'en',
          hfToken: AppConfig.hfToken,
        );
      }
      await MicroCoachingService.launch(chwId);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _launching
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(AssistantStrings.launchingMicroCoaching),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null) ...[
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        AssistantStrings.errorMessage,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  ElevatedButton.icon(
                    onPressed: _launch,
                    icon: const Icon(Icons.school_outlined),
                    label: Text(AssistantStrings.openMicroCoaching),
                  ),
                ],
              ),
      ),
    );
  }
}
