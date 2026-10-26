# Política de privacidad · Privacy Policy

**Allowance Privacy** · Última actualización / Last updated: 2026-10-26 · Versión 0.2.0

[Español](#español) · [English](#english)

---

## Español

### Resumen

Allowance Privacy no recoge, envía ni vende ningún dato. No hay cuentas, anuncios, analíticas ni telemetría. La versión publicada **no tiene permiso de acceso a Internet**, así que no puede enviar nada a ningún servidor.

### Qué datos guarda y dónde

Todo se guarda **solo en tu dispositivo**, dentro del espacio privado de la app:

- **Presupuesto y movimientos** (importe, descripción y fecha), en una base de datos local.
- **Ajustes**: moneda, idioma, tema, vibración, recordatorios y opciones de privacidad.
- **PIN de bloqueo**: nunca se guarda el PIN, solo una huella criptográfica irreversible (Argon2id con sal) y el contador de intentos fallidos.

La base de datos local no está cifrada; la protege el aislamiento de Android entre apps. Estos datos están excluidos de la copia en la nube de Android y de la transferencia entre dispositivos.

### Huella dactilar

La comprobación la hace Android. La app solo recibe si ha sido correcta o no; nunca accede a tu huella.

### Copias de seguridad y exportaciones

Solo se crean cuando tú lo decides, en el archivo o carpeta que tú eliges:

- **CSV**: movimientos sin cifrar, para usarlos en otras apps.
- **Backup completo**: cifrado con tu contraseña (AES-256-GCM + Argon2id), salvo que elijas expresamente no cifrarlo.
- **AutoBackup**: siempre cifrado, en la carpeta que elijas. La clave se protege con el almacén de claves de Android; tu contraseña no se guarda.

Si guardas esos archivos en una carpeta sincronizada (por ejemplo, Google Drive), el servicio que elijas se rige por su propia política.

### Permisos

| Permiso | Para qué |
|---|---|
| Biometría | Desbloquear la app con tu huella, si lo activas |
| Notificaciones, vibración y arranque | Recordatorios diarios locales, que no contienen importes, y reprogramarlos tras reiniciar |

### Enlaces externos

Los enlaces de Ajustes (GitHub, donaciones, contacto) se abren en tu navegador o en otra app y se rigen por sus propias políticas. La app no les envía ningún dato.

### Menores

La app no recoge datos de nadie, tampoco de menores.

### Cambios y contacto

Los cambios en esta política quedan registrados en el historial de este repositorio.
Contacto: [d4vram369@proton.me](mailto:d4vram369@proton.me) · [Telegram](https://t.me/D4vRAM369)

---

## English

### Summary

Allowance Privacy does not collect, send or sell any data. There are no accounts, ads, analytics or telemetry. The released version **has no Internet permission**, so it cannot send anything to any server.

### What is stored and where

Everything stays **only on your device**, inside the app's private storage:

- **Budget and transactions** (amount, description and date), in a local database.
- **Settings**: currency, language, theme, haptics, reminders and privacy options.
- **Lock PIN**: the PIN itself is never stored, only an irreversible cryptographic hash (salted Argon2id) and the failed-attempt counter.

The local database is not encrypted; it is protected by Android's app sandbox. This data is excluded from Android cloud backup and device-to-device transfer.

### Fingerprint

Android performs the check. The app only learns whether it succeeded; it never accesses your fingerprint.

### Backups and exports

They are created only when you decide, in the file or folder you choose:

- **CSV**: unencrypted transactions, for use in other apps.
- **Full backup**: encrypted with your password (AES-256-GCM + Argon2id), unless you explicitly choose not to encrypt it.
- **AutoBackup**: always encrypted, in the folder you choose. The key is protected by the Android Keystore; your password is not stored.

If you save those files to a synced folder (for example, Google Drive), the service you choose is governed by its own policy.

### Permissions

| Permission | Purpose |
|---|---|
| Biometrics | Unlock the app with your fingerprint, if enabled |
| Notifications, vibration and boot | Local daily reminders, which contain no amounts, rescheduled after a restart |

### External links

Links in Settings (GitHub, donations, contact) open in your browser or another app and are governed by their own policies. The app sends them no data.

### Children

The app collects no data from anyone, including children.

### Changes and contact

Changes to this policy are recorded in this repository's history.
Contact: [d4vram369@proton.me](mailto:d4vram369@proton.me) · [Telegram](https://t.me/D4vRAM369)
