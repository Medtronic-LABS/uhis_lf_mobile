import 'package:flutter/material.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';

/// Initials avatar + role + full name + raw login username card, built from
/// [UserProfileSummary]. Shared by the Lock screen and [SettingsScreen] so
/// both surfaces show the signed-in user's identity identically.
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.summary, this.username});

  final UserProfileSummary summary;

  /// Raw login identifier (`AuthState.username`) — distinct from the
  /// display name derived from [summary]; shown alongside it so the SK can
  /// confirm which account is signed in.
  final String? username;

  String _initials() {
    final f = summary.firstName?.trim() ?? '';
    final l = summary.lastName?.trim() ?? '';
    final fi = f.isNotEmpty ? f[0].toUpperCase() : '';
    final li = l.isNotEmpty ? l[0].toUpperCase() : '';
    final result = '$fi$li';
    return result.isNotEmpty ? result : '?';
  }

  String _fullName() {
    final f = summary.firstName?.trim() ?? '';
    final l = summary.lastName?.trim() ?? '';
    return [f, l].where((e) => e.isNotEmpty).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.h4xl,
        AppSpacing.xxxl,
        AppSpacing.h4xl,
        AppSpacing.xxxl,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.profileCard),
        boxShadow: AppShadows.profileCard,
      ),
      child: Row(
        children: [
          // Initials avatar — pink background
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.pink.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(),
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.pink,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Name + role
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LockStrings.shasthyaKormi,
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy.withValues(alpha: 0.45),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _fullName().isNotEmpty
                      ? _fullName()
                      : LockStrings.profileLoading,
                  style: const TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                    letterSpacing: -0.2,
                  ),
                ),
                if (username != null && username!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${LoginStrings.usernameLabel}: $username',
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
