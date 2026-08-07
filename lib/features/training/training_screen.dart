import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/micro_coaching_service.dart';

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
  }

  Future<void> _launch() async {
    setState(() { _busy = true; _error = null; });
    try {
      final repo = context.read<AuthRepository>();
      final userId = await repo.userId();
      final chwId = userId?.toString() ?? 'chw_unknown';
      debugPrint('[MicroCoaching] TrainingScreen: userId=$userId chwId=$chwId');
      final initialized = await MicroCoachingService.isInitialized();
      debugPrint('[MicroCoaching] TrainingScreen: isInitialized=$initialized');
      await MicroCoachingService.launch(chwId);
      debugPrint('[MicroCoaching] TrainingScreen: launch returned (user came back from SDK)');
    } catch (e) {
      debugPrint('[MicroCoaching] TrainingScreen: launch error=$e');
      if (mounted) setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(TrainingStrings.loadFailedGeneric, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _launch, child: Text(CommonStrings.retry)),
                ],
              )
            : _busy ? const CircularProgressIndicator() : const SizedBox.shrink(),
      ),
    );
  }
}
