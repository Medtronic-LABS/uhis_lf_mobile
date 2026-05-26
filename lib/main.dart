import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/api/api_client.dart';
import 'core/auth/auth_repository.dart';
import 'core/auth/auth_state.dart';
import 'core/auth/biometric_service.dart';
import 'core/config/app_config.dart';
import 'features/dashboard/dashboard_repository.dart';
import 'features/lock/lock_barrier.dart';
import 'features/search/global_search_repository.dart';
import 'features/search/household_search_repository.dart';
import 'features/search/patient_search_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final api = await ApiClient.create();
  final authRepo = AuthRepository(api);
  final biometric = BiometricService();
  final authState = AuthState(authRepo, biometric);
  await authState.bootstrap();
  final bioEnabled = await authRepo.isBiometricEnabled();
  if (AppConfig.hasDevCredentials &&
      !bioEnabled &&
      authState.status == AuthStatus.signedOut) {
    // ignore: avoid_print
    print('[DEV-AUTOLOGIN] attempting ${AppConfig.devUser}');
    final ok = await authState.login(AppConfig.devUser, AppConfig.devPass);
    // ignore: avoid_print
    print('[DEV-AUTOLOGIN] result=$ok error=${authState.error}');
  }
  runApp(UhisNextApp(
    api: api,
    authRepo: authRepo,
    authState: authState,
    biometric: biometric,
  ));
}

class UhisNextApp extends StatefulWidget {
  const UhisNextApp({
    super.key,
    required this.api,
    required this.authRepo,
    required this.authState,
    required this.biometric,
  });

  final ApiClient api;
  final AuthRepository authRepo;
  final AuthState authState;
  final BiometricService biometric;

  @override
  State<UhisNextApp> createState() => _UhisNextAppState();
}

class _UhisNextAppState extends State<UhisNextApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      widget.authState.lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: widget.api),
        Provider<AuthRepository>.value(value: widget.authRepo),
        Provider<BiometricService>.value(value: widget.biometric),
        ChangeNotifierProvider<AuthState>.value(value: widget.authState),
        Provider<DashboardRepository>(
            create: (_) => DashboardRepository(widget.api)),
        Provider<PatientSearchRepository>(
            create: (_) => PatientSearchRepository(widget.api)),
        Provider<HouseholdSearchRepository>(
            create: (_) => HouseholdSearchRepository(widget.api)),
        ProxyProvider2<PatientSearchRepository, HouseholdSearchRepository,
            GlobalSearchRepository>(
          update: (_, p, h, __) => GlobalSearchRepository(p, h),
        ),
      ],
      child: Builder(
        builder: (context) {
          final router = buildRouter(context.read<AuthState>());
          return MaterialApp.router(
            title: 'UHIS Next',
            theme: buildAppTheme(),
            routerConfig: router,
            debugShowCheckedModeBanner: false,
            builder: (ctx, child) {
              final auth = ctx.watch<AuthState>();
              final showBarrier = auth.status == AuthStatus.signedIn &&
                  auth.locked &&
                  auth.biometricEnabled;
              return Stack(
                children: [
                  child ?? const SizedBox.shrink(),
                  if (showBarrier) const Positioned.fill(child: LockBarrier()),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
