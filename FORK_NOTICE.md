# Allowance Privacy

Fork Android independiente de [Allowance](https://github.com/jameskokoska/Allowance), creado por James Kokoska y sus colaboradores.

Allowance Privacy: Copyright (C) 2026 [D4vRAM369](https://github.com/D4vRAM369), autor del fork y de sus modificaciones. Distribuido bajo GPL-3.0, como el original. Versión 0.2.0.

Base inicial: commit `650467e` (Version bump). Se conserva íntegro LICENSE (GPL-3.0) y la atribución original. El README original se conserva después del aviso del fork.

Cambios iniciados el 26 de octubre de 2026: identidad Android `dev.d4vram.allowanceenhanced`, nombre visible Allowance Privacy, versión 0.1.0+1, icono propio y documentación PBL.

Este fork no es una publicación del autor original. No se accede al almacenamiento privado de la aplicación original.

Al distribuir binarios, proporcionar el código fuente correspondiente y los avisos y derechos exigidos por GPL-3.0. No se añade una licencia restrictiva al fork.

Sesión3: se incorporan intercambio CSV, backup lógico con AES256GCM/Argon2id mediante cryptography (dependencia Apache2 autorizada, avisos mantenidos por Flutter), AutoBackup con SAF/Keystore/JobScheduler y edición de descripciones. SQLite actualizada a0.5.28 conservando esquema. Sin implementación de PIN/biometría/ocultación todavía.

Sesión5: bloqueo con PIN (hash Argon2id), huella (`local_auth`, BSD-3) y bloqueo automático; ocultación de importes centralizada; bloqueo opcional de capturas (FLAG_SECURE) y ocultación en apps recientes. Retirados del fork, porque no funcionaban con el nuevo identificador y añadían telemetría de Google y permiso de red: donaciones (`in_app_purchase`), petición de reseña (`in_app_review`) y promoción de Cashew. La versión release no solicita permiso INTERNET. El crédito al proyecto original se mantiene en Ajustes y en este aviso.
