import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:budget_simple/security/app_lock.dart';
import 'package:budget_simple/security/pin_pad.dart';
import 'package:budget_simple/struct/database_global.dart';

Future<bool> deviceBiometric() async {
  try {
    return await withOwnSheet(() => LocalAuthentication().authenticate(
        localizedReason: 'Desbloquear Allowance Privacy',
        options:
            const AuthenticationOptions(biometricOnly: true, stickyAuth: true)));
  } on PlatformException {
    // No hardware, nothing enrolled or locked out: the PIN still works.
    return false;
  }
}

/// Sits above the Navigator. While locked the app stays alive but Offstage:
/// not painted, not in the accessibility tree, so no financial frame leaks.
class LockGate extends StatefulWidget {
  const LockGate(
      {super.key,
      required this.lock,
      required this.child,
      this.biometricAuth = deviceBiometric});

  final AppLock lock;
  final Widget child;
  final Future<bool> Function() biometricAuth;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  late bool locked = widget.lock.enabled;
  DateTime? hiddenAt;
  // The biometric sheet itself can pause the activity; that is not "leaving".
  bool authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (locked) WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (authenticating || ownSheetOpen) return;
    // Privacy mode re-engages every time the user really leaves the app.
    if (state == AppLifecycleState.paused &&
        (widget.lock.prefs.getBool(hideAmountsKey) ?? false)) {
      amountsHidden.value = true;
    }
    if (!widget.lock.enabled) return;
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      hiddenAt ??= widget.lock.clock();
      // Immediate lock is applied before leaving, so resume never shows data.
      if (widget.lock.timeout == Duration.zero) setState(() => locked = true);
    } else if (state == AppLifecycleState.resumed) {
      final since = hiddenAt;
      hiddenAt = null;
      if (since == null) return;
      if (locked ||
          widget.lock.clock().difference(since) >= widget.lock.timeout) {
        setState(() => locked = true);
        _biometric();
      }
    }
  }

  Future<void> _biometric() async {
    if (!locked || authenticating || !widget.lock.biometric) return;
    authenticating = true;
    final ok = await widget.biometricAuth();
    authenticating = false;
    hiddenAt = null;
    if (ok && mounted) setState(() => locked = false);
  }

  Future<String?> _unlock(String pin) async {
    if (await widget.lock.verify(pin)) {
      if (mounted) setState(() => locked = false);
      return null;
    }
    final wait = widget.lock.blockedFor;
    return wait == null
        ? 'PIN incorrecto.'
        : 'Demasiados intentos. Espera ${wait.inSeconds + 1} s.';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Offstage(
          offstage: locked,
          child: TickerMode(enabled: !locked, child: widget.child)),
      if (locked)
        Positioned.fill(
          child: Material(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  child: PinPad(
                    title: 'Allowance Privacy está bloqueada',
                    subtitle: 'Introduce tu PIN',
                    onSubmit: _unlock,
                    extra: widget.lock.biometric
                        ? TextButton.icon(
                            onPressed: _biometric,
                            icon: const Icon(Icons.fingerprint),
                            label: const Text('Usar huella'))
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}
