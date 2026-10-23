import 'package:flutter/material.dart';

import 'Services/admin_access_service.dart';

typedef AdminAccessCheck = Future<AdminAccessResult> Function();

class AdminAccessGuard extends StatefulWidget {
  const AdminAccessGuard({
    super.key,
    required this.child,
    this.accessCheck,
    this.requiredPermissions = const {},
  });

  final Widget child;
  final AdminAccessCheck? accessCheck;
  final Set<String> requiredPermissions;

  @override
  State<AdminAccessGuard> createState() => _AdminAccessGuardState();
}

class _AdminAccessGuardState extends State<AdminAccessGuard> {
  late final Future<AdminAccessResult> _access;

  @override
  void initState() {
    super.initState();
    _access =
        widget.accessCheck?.call() ?? AdminAccessService().checkCurrentUser();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AdminAccessResult>(
    future: _access,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }

      final result = snapshot.data;
      final missingPermission =
          result?.isAllowed == true &&
          !widget.requiredPermissions.every(result!.permissions.contains);
      if (result?.isAllowed == true && !missingPermission) return widget.child;

      return _AdminAccessDenied(
        message: missingPermission
            ? 'Your administrator role does not have access to this page.'
            : result?.status == AdminAccessStatus.unavailable
            ? 'Administrator access could not be verified. Please try again.'
            : 'An active administrator account is required.',
      );
    },
  );
}

class _AdminAccessDenied extends StatelessWidget {
  const _AdminAccessDenied({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.admin_panel_settings_outlined, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/', (_) => false),
              child: const Text('Return to sign in'),
            ),
          ],
        ),
      ),
    ),
  );
}
