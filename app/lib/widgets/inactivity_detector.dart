import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Wraps a child widget and monitors user activity.
/// After [timeoutMinutes] of inactivity, calls [onTimeout] (auto-logout).
/// Shows a warning dialog [warningBeforeSeconds] before the timeout fires.
class InactivityDetector extends StatefulWidget {
  final Widget child;
  final int timeoutMinutes;
  final VoidCallback onTimeout;

  /// How many seconds before final timeout to show the "still there?" dialog.
  final int warningBeforeSeconds;

  const InactivityDetector({
    super.key,
    required this.child,
    required this.timeoutMinutes,
    required this.onTimeout,
    this.warningBeforeSeconds = 60,
  });

  @override
  State<InactivityDetector> createState() => _InactivityDetectorState();
}

class _InactivityDetectorState extends State<InactivityDetector>
    with WidgetsBindingObserver {
  Timer? _logoutTimer;
  Timer? _warningTimer;
  Timer? _countdownTicker;
  bool _warningVisible = false;
  int _secondsRemaining = 0;

  Duration get _timeout => Duration(minutes: widget.timeoutMinutes);

  Duration get _warningAt =>
      _timeout - Duration(seconds: widget.warningBeforeSeconds);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetTimers();
  }

  @override
  void dispose() {
    _logoutTimer?.cancel();
    _warningTimer?.cancel();
    _countdownTicker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app goes to background, keep the timer running.
    // When user returns, if timer expired, they'll be logged out immediately.
    if (state == AppLifecycleState.resumed) {
      // Timer still ticking — no extra action needed.
    }
  }

  void _resetTimers() {
    if (widget.timeoutMinutes <= 0) return; // disabled

    _logoutTimer?.cancel();
    _warningTimer?.cancel();
    _countdownTicker?.cancel();

    if (_warningVisible) {
      _warningVisible = false;
      // Pop the dialog if it's showing
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }

    // Set the warning timer (fires warningBeforeSeconds before logout)
    if (_warningAt.inSeconds > 0) {
      _warningTimer = Timer(_warningAt, _showWarning);
    }

    // Set the final logout timer
    _logoutTimer = Timer(_timeout, _doTimeout);
  }

  void _showWarning() {
    if (!mounted) return;
    _secondsRemaining = widget.warningBeforeSeconds;
    _warningVisible = true;

    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsRemaining--;
        if (_secondsRemaining <= 0) {
          _countdownTicker?.cancel();
        }
      });
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SessionWarningDialog(
        secondsRemaining: () => _secondsRemaining,
        onStayLoggedIn: () {
          Navigator.of(ctx).pop();
          _warningVisible = false;
          _countdownTicker?.cancel();
          _resetTimers();
        },
      ),
    );
  }

  void _doTimeout() {
    _logoutTimer?.cancel();
    _warningTimer?.cancel();
    _countdownTicker?.cancel();

    // Dismiss any open dialog
    if (mounted && _warningVisible) {
      Navigator.of(context).pop();
      _warningVisible = false;
    }

    widget.onTimeout();
  }

  void _onUserActivity() {
    if (!_warningVisible) {
      _resetTimers();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.timeoutMinutes <= 0) return widget.child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onUserActivity(),
      onPointerMove: (_) => _onUserActivity(),
      child: widget.child,
    );
  }
}

/// The "Session expiring" warning dialog with live countdown.
class _SessionWarningDialog extends StatefulWidget {
  final int Function() secondsRemaining;
  final VoidCallback onStayLoggedIn;

  const _SessionWarningDialog({
    required this.secondsRemaining,
    required this.onStayLoggedIn,
  });

  @override
  State<_SessionWarningDialog> createState() => _SessionWarningDialogState();
}

class _SessionWarningDialogState extends State<_SessionWarningDialog> {
  late Timer _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secs = widget.secondsRemaining();
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFFFA726), width: 1.5),
      ),
      icon: const Icon(Icons.timer_outlined, color: Color(0xFFFFA726), size: 40),
      title: Text(
        'Session Expiring',
        style: GoogleFonts.outfit(
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'You will be logged out due to inactivity.',
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Countdown badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFA726).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${secs}s remaining',
              style: GoogleFonts.dmMono(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFFFA726),
              ),
            ),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: widget.onStayLoggedIn,
            icon: const Icon(Icons.touch_app_rounded),
            label: const Text('Stay Logged In'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFA726),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
