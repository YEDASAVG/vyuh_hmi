import 'package:flutter/material.dart';

import '../config/hmi_theme_engine.dart';
import '../services/auth_service.dart';

/// Electronic signature dialog — 21 CFR Part 11 compliant.
///
/// Requires re-authentication (username + password + reason) before
/// critical PLC writes such as emergency stop or agitator override.
///
/// Returns `true` if the signature was verified successfully.
class ESignatureDialog extends StatefulWidget {
  final AuthService authService;
  final String action; // e.g. "Emergency Stop", "Set Agitator RPM"

  const ESignatureDialog({
    super.key,
    required this.authService,
    required this.action,
  });

  /// Show the dialog and return true if e-signature was verified.
  static Future<bool> show(
    BuildContext context, {
    required AuthService authService,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ESignatureDialog(
        authService: authService,
        action: action,
      ),
    );
    return result ?? false;
  }

  @override
  State<ESignatureDialog> createState() => _ESignatureDialogState();
}

class _ESignatureDialogState extends State<ESignatureDialog> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isVerifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-fill username from current session
    final user = widget.authService.currentUser;
    if (user != null) {
      _usernameCtrl.text = user.username;
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_usernameCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Username and password are required');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    final ok = await widget.authService.verifyESignature(
      username: _usernameCtrl.text,
      password: _passwordCtrl.text,
      reason: widget.action,
    );

    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isVerifying = false;
        _error = 'Verification failed — invalid credentials';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ActiveTheme.of(context);

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.danger.withValues(alpha: 0.5)),
      ),
      title: Row(
        children: [
          Icon(Icons.verified_user_rounded, color: colors.danger, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Electronic Signature Required',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: 'DM Mono',
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: colors.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Action: ${widget.action}',
                      style: TextStyle(
                        color: colors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'DM Mono',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Re-enter credentials to authorize this critical operation.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameCtrl,
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Username',
                labelStyle: TextStyle(color: colors.textSecondary),
                prefixIcon:
                    Icon(Icons.person_outline, color: colors.textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.surfaceBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.accent),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
              onSubmitted: (_) => _verify(),
              decoration: InputDecoration(
                labelText: 'Password',
                labelStyle: TextStyle(color: colors.textSecondary),
                prefixIcon:
                    Icon(Icons.lock_outline, color: colors.textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.surfaceBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.accent),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: colors.danger, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isVerifying ? null : () => Navigator.of(context).pop(false),
          child: Text('Cancel',
              style: TextStyle(color: colors.textSecondary)),
        ),
        FilledButton.icon(
          onPressed: _isVerifying ? null : _verify,
          icon: _isVerifying
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.verified_outlined, size: 16),
          label: Text(_isVerifying ? 'Verifying...' : 'Sign & Authorize'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.danger,
          ),
        ),
      ],
    );
  }
}
