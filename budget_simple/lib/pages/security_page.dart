import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:budget_simple/security/app_lock.dart';
import 'package:budget_simple/security/lock_gate.dart';
import 'package:budget_simple/security/pin_pad.dart';
import 'package:budget_simple/struct/database_global.dart';

const secureScreenKey = 'secureScreen';
const hideInRecentsKey = 'hideInRecents';

/// MainActivity reads the same preferences; this re-applies them right away.
Future<void> applyScreenProtection() => const MethodChannel(
        'allowance_privacy/screen')
    .invokeMethod<void>('apply')
    .catchError((_) {});

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});
  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  final lock = AppLock(sharedPreferences);
  bool canBiometric = false;

  @override
  void initState() {
    super.initState();
    LocalAuthentication()
        .canCheckBiometrics
        .then((value) => mounted ? setState(() => canBiometric = value) : null)
        .catchError((_) {});
  }

  Future<String?> _checkCurrent(String pin) async {
    if (await lock.verify(pin)) return null;
    final wait = lock.blockedFor;
    return wait == null
        ? 'PIN incorrecto.'
        : 'Demasiados intentos. Espera ${wait.inSeconds + 1} s.';
  }

  Future<bool> _confirmCurrent() async =>
      await askPin(context, title: 'PIN actual', check: _checkCurrent) != null;

  Future<void> _newPin() async {
    final first = await askPin(context,
        title: 'Nuevo PIN',
        subtitle: 'Entre 6 y 8 dígitos.',
        check: (pin) async =>
            AppLock.validPin(pin) ? null : 'Usa entre 6 y 8 dígitos.');
    if (first == null || !mounted) return;
    final second = await askPin(context,
        title: 'Repite el PIN',
        check: (pin) async => pin == first ? null : 'Los PIN no coinciden.');
    if (second == null) return;
    await lock.setPin(second);
    if (mounted) setState(() {});
  }

  Future<void> _toggleLock(bool on) async {
    if (on) {
      await _newPin();
    } else if (await _confirmCurrent()) {
      await lock.disable();
      if (mounted) setState(() {});
    }
  }

  Future<void> _toggleBiometric(bool on) async {
    if (on && !await deviceBiometric()) return;
    await sharedPreferences.setBool(AppLock.biometricKey, on);
    if (mounted) setState(() {});
  }

  Future<void> _setScreen(String key, bool value) async {
    await sharedPreferences.setBool(key, value);
    await applyScreenProtection();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final enabled = lock.enabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacidad y seguridad')),
      body: ListView(children: [
        SwitchListTile(
          secondary: const Icon(Icons.visibility_off_outlined),
          title: const Text('Ocultar importes'),
          subtitle: const Text(
              'Muestra •••• en lugar de cantidades al abrir o volver a la app. El ojo de la pantalla principal las enseña un momento.'),
          value: sharedPreferences.getBool(hideAmountsKey) ?? false,
          onChanged: (value) async {
            await sharedPreferences.setBool(hideAmountsKey, value);
            amountsHidden.value = value;
            if (mounted) setState(() {});
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.screenshot_monitor_outlined),
          title: const Text('Bloquear capturas de pantalla'),
          subtitle: const Text(
              'Impide capturas y grabaciones; la vista de recientes se verá en negro.'),
          value: sharedPreferences.getBool(secureScreenKey) ?? false,
          onChanged: (value) => _setScreen(secureScreenKey, value),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.layers_clear_outlined),
          title: const Text('Ocultar en apps recientes'),
          subtitle: const Text(
              'Tapa la miniatura del selector de apps. Android 13 o superior; en versiones anteriores usa «Bloquear capturas».'),
          value: sharedPreferences.getBool(hideInRecentsKey) ?? true,
          onChanged: (value) => _setScreen(hideInRecentsKey, value),
        ),
        const Divider(),
        SwitchListTile(
          title: const Text('Bloqueo con PIN'),
          subtitle: const Text(
              'Pide el PIN antes de mostrar tus datos. Si lo olvidas no hay forma de recuperarlo: solo tus copias de seguridad.'),
          value: enabled,
          onChanged: _toggleLock,
        ),
        if (enabled) ...[
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Cambiar PIN'),
            onTap: () async {
              if (await _confirmCurrent()) await _newPin();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Desbloquear con huella'),
            subtitle: Text(canBiometric
                ? 'Usa la biometría del sistema. El PIN sigue funcionando.'
                : 'No hay biometría disponible en este dispositivo.'),
            value: lock.biometric,
            onChanged: canBiometric ? _toggleBiometric : null,
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Bloquear al salir de la app'),
            trailing: DropdownButton<int>(
              value: lock.timeout.inSeconds,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Inmediato')),
                DropdownMenuItem(value: 30, child: Text('30 s')),
                DropdownMenuItem(value: 60, child: Text('1 min')),
                DropdownMenuItem(value: 300, child: Text('5 min')),
              ],
              onChanged: (value) async {
                await sharedPreferences.setInt(AppLock.timeoutKey, value!);
                if (mounted) setState(() {});
              },
            ),
          ),
        ],
      ]),
    );
  }
}
