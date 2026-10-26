import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:budget_simple/backup/backup_crypto.dart';
import 'package:budget_simple/backup/backup_service.dart';
import 'package:budget_simple/backup/data_transfer.dart';
import 'package:budget_simple/struct/database_global.dart';
import 'package:budget_simple/struct/languages_dict.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  late final service = BackupService(database, sharedPreferences);
  Map<String, dynamic> status = {};
  bool busy = false;
  bool encrypt = true;
  int hours = 24;
  int retention = 7;
  String? message;

  @override
  void initState() {
    super.initState();
    _run(_refresh);
  }

  Future<void> _refresh() async {
    final value = await service.platform.status();
    if (!mounted) return;
    setState(() {
      status = value;
      hours = (value['intervalHours'] as num?)?.toInt() ?? 24;
      retention = (value['retention'] as num?)?.toInt() ?? 7;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } on PlatformException {
      if (mounted) {
        setState(() => message =
            'No se pudo acceder al archivo, carpeta o clave. Revisa los permisos y el espacio disponible.');
      }
    } catch (_) {
      // Never display parser exceptions: they can include financial contents.
      if (mounted) {
        setState(() => message =
            'No se completó la operación. Comprueba formato, contraseña y espacio. Los datos existentes se conservan si la importación falla.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _success(String value) {
    if (mounted) setState(() => message = value);
  }

  Future<bool> _confirm(String title, String description) async {
    if (!mounted) return false;
    return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: Text(title),
                    content: SingleChildScrollView(child: Text(description)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Confirmar'))
                    ])) ??
        false;
  }

  Future<String?> _password({required bool creating}) async {
    if (!mounted) return null;
    final first = TextEditingController();
    final second = TextEditingController();
    String? error;
    try {
      return await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) => StatefulBuilder(
              builder: (context, update) => AlertDialog(
                      title: Text(creating
                          ? 'Contraseña de la copia'
                          : 'Abrir copia cifrada'),
                      content: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(creating
                            ? 'Usa al menos 12 caracteres. Necesitarás esta contraseña para recuperar las copias, incluso en otro dispositivo. Si la pierdes no podremos recuperarlas.'
                            : 'Introduce la contraseña con la que se creó la copia.'),
                        TextField(
                            controller: first,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            maxLength: 1024,
                            decoration: const InputDecoration(
                                labelText: 'Contraseña', counterText: '')),
                        if (creating)
                          TextField(
                              controller: second,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              maxLength: 1024,
                              decoration: const InputDecoration(
                                  labelText: 'Repetir contraseña',
                                  counterText: '')),
                        if (error != null)
                          Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                      ])),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancelar')),
                        FilledButton(
                            onPressed: () {
                              if ((creating && first.text.runes.length < 12) ||
                                  first.text.isEmpty ||
                                  (creating && first.text != second.text)) {
                                update(() => error =
                                    'Revisa la longitud y que ambas contraseñas coincidan.');
                                return;
                              }
                              Navigator.pop(context, first.text);
                            },
                            child: const Text('Continuar')),
                      ])));
    } finally {
      // Let the dismissed route release its TextFields before disposing.
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        first.dispose();
        second.dispose();
      });
    }
  }

  String _name(String extension) =>
      'allowance-privacy-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}$extension';

  Future<void> _exportCsv() async {
    if (!await _confirm('CSV sin cifrar',
        'El archivo contiene movimientos legibles por cualquiera que tenga acceso. No incluye presupuesto ni ajustes.')) {
      return;
    }
    final rows = (await service.snapshot()).transactions;
    final bytes = Uint8List.fromList(utf8.encode(TransactionCsv.encode(rows)));
    if (await service.platform
        .writeDocument(_name('.csv'), 'text/csv', bytes)) {
      _success('CSV exportado: ${rows.length} movimientos.');
    }
  }

  Future<void> _importCsv() async {
    final bytes = await service.platform.readDocument();
    if (bytes == null) return;
    final rows = TransactionCsv.decode(utf8.decode(bytes));
    final preview = rows
        .take(3)
        .map((row) => '${row.date.toLocal()} · ${row.name} · ${row.amount}')
        .join('\n');
    if (!await _confirm('Importar ${rows.length} movimientos',
        '$preview\n\nSe añadirán los movimientos sin modificar el presupuesto. Se omiten coincidencias exactas de fecha, concepto e importe.')) {
      return;
    }
    final count = await DataTransfer(database).importCsv(rows);
    _success(
        'Importados $count movimientos; ${rows.length - count} duplicados omitidos.');
  }

  Future<void> _exportBackup() async {
    final String? password;
    if (encrypt) {
      password = await _password(creating: true);
      if (password == null) return;
    } else {
      password = null;
      if (!await _confirm('Backup sin cifrar',
          'Esta copia contiene presupuesto, movimientos y ajustes de moneda, idioma, tema y vibración en texto legible.')) {
        return;
      }
    }
    final bytes = await service.createBackup(password: password);
    if (await service.platform
        .writeDocument(_name('.apbackup'), 'application/octet-stream', bytes)) {
      _success(
          'Copia completa guardada${encrypt ? ' con contraseña' : ' sin cifrar'}.');
    }
  }

  Future<void> _restore() async {
    final bytes = await service.platform.readDocument();
    if (bytes == null) return;
    String? password;
    final encrypted = BackupCrypto.isEncrypted(bytes);
    if (encrypted) {
      password = await _password(creating: false);
      if (password == null) return;
    }
    final data = await service.parseBackup(bytes, password: password);
    if (!await _confirm(
        'Restaurar copia completa',
        '${encrypted ? 'Copia cifrada y autenticada con su contraseña.' : 'Copia SIN cifrar: su autenticidad no está protegida.'}\n'
        '${data.transactions.length} movimientos. Presupuesto: ${data.budget.amount}.\n'
            'Sustituirá todos los movimientos y el presupuesto actuales, además de los ajustes incluidos. '
            'Exporta primero una copia de tus datos actuales si deseas conservarlos.')) {
      return;
    }
    await service.restore(data);
    currencyIcon = sharedPreferences.getString('currencyIcon') ?? '\$';
    language = sharedPreferences.getString('language') ??
        (getDeviceLanguage() ?? 'en');
    themeMode = sharedPreferences.getString('themeMode') ?? 'System';
    _success(
        'Copia restaurada. Los ajustes de apariencia se aplicarán completamente al volver a abrir la app.');
  }

  Future<void> _configure() async {
    if (status['folderSelected'] != true &&
        !await service.platform.pickFolder()) return;
    final password = await _password(creating: true);
    if (password == null) {
      await _refresh();
      return;
    }
    final material = await BackupCrypto.createMaterial(password);
    try {
      await service.platform.configure(material['key']!, material['salt']!,
          hours: hours, retention: retention);
    } finally {
      material['key']!.fillRange(0, material['key']!.length, 0);
    }
    await _refresh();
    _success(
        'AutoBackup activado y cifrado. Android puede aplazar las copias para ahorrar batería.');
  }

  @override
  Widget build(BuildContext context) {
    final enabled = status['enabled'] == true;
    final last = status['lastSuccess'];
    return PopScope(
        canPop: !busy,
        child: Scaffold(
            appBar: AppBar(title: const Text('Copias y datos')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              if (busy)
                const LinearProgressIndicator(
                    semanticsLabel: 'Operación en curso'),
              if (message != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(message!, semanticsLabel: message)),
              const Text('CSV · intercambio',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Text(
                  'Formato: date,name,amount. Fechas ISO 8601 UTC y punto decimal. Sin contraseña. Solo movimientos.'),
              ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('Exportar CSV sin cifrar'),
                  onTap: busy ? null : () => _run(_exportCsv)),
              ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Importar CSV sin cifrar'),
                  onTap: busy ? null : () => _run(_importCsv)),
              const Divider(),
              const Text('Backup completo',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Text(
                  'Presupuesto, movimientos y ajustes admitidos. No incluye PIN, credenciales ni configuración de AutoBackup.'),
              SwitchListTile(
                  title: const Text('Cifrar con contraseña'),
                  value: encrypt,
                  subtitle: const Text('AES-256-GCM · Argon2id'),
                  onChanged:
                      busy ? null : (value) => setState(() => encrypt = value)),
              ListTile(
                  leading: const Icon(Icons.save_outlined),
                  title: const Text('Crear backup'),
                  onTap: busy ? null : () => _run(_exportBackup)),
              ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Restaurar backup'),
                  onTap: busy ? null : () => _run(_restore)),
              const Divider(),
              const Text('AutoBackup cifrado',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Text(
                  'Carpeta elegida por ti, sin nube integrada. Las copias pueden sobrevivir a la desinstalación: guarda su contraseña. Requiere Android 6 o posterior.'),
              ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(status['folderSelected'] == true
                      ? 'Carpeta seleccionada · cambiar'
                      : 'Elegir carpeta'),
                  onTap: busy
                      ? null
                      : () => _run(() async {
                            await service.platform.pickFolder();
                            await _refresh();
                          })),
              DropdownButtonFormField<int>(
                  value: hours,
                  decoration: const InputDecoration(labelText: 'Frecuencia'),
                  items: const [
                    DropdownMenuItem(value: 24, child: Text('Diaria')),
                    DropdownMenuItem(value: 168, child: Text('Semanal'))
                  ],
                  onChanged: busy || enabled
                      ? null
                      : (v) => setState(() => hours = v!)),
              DropdownButtonFormField<int>(
                  value: retention,
                  decoration:
                      const InputDecoration(labelText: 'Copias a conservar'),
                  items: [3, 7, 14]
                      .map((n) =>
                          DropdownMenuItem(value: n, child: Text('$n copias')))
                      .toList(),
                  onChanged: busy || enabled
                      ? null
                      : (v) => setState(() => retention = v!)),
              SwitchListTile(
                  title: const Text('Activar AutoBackup'),
                  value: enabled,
                  subtitle: const Text(
                      'Para cambiar contraseña o frecuencia, desactiva y configura de nuevo.'),
                  onChanged: busy
                      ? null
                      : (value) => _run(() async {
                            if (value) {
                              await _configure();
                            } else {
                              await service.platform.disable();
                              await _refresh();
                            }
                          })),
              if (enabled)
                ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('Crear copia automática ahora'),
                    onTap: busy
                        ? null
                        : () => _run(() async {
                              await service.runAutomatic();
                              await _refresh();
                              _success('Copia cifrada verificada y guardada.');
                            })),
              Text(last is num && last > 0
                  ? 'Última copia: ${DateTime.fromMillisecondsSinceEpoch(last.toInt()).toLocal()}'
                  : 'Todavía no hay copias automáticas correctas.'),
              if (status['lastError'] != null)
                const Text(
                    'La última copia automática falló. Comprueba la carpeta y vuelve a intentarlo.'),
              const SizedBox(height: 24),
            ])));
  }
}
