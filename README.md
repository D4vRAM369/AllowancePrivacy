# Allowance Privacy

Fork Android de [Allowance](https://github.com/jameskokoska/Allowance) centrado en proteger tu información financiera. Se instala junto a la app original (`dev.d4vram.allowanceenhanced`) y conserva todas sus funciones de presupuesto. Origen, cambios y licencia: [FORK_NOTICE.md](FORK_NOTICE.md) (GPL-3.0).

**Fork creado y mantenido por [D4vRAM369](https://github.com/D4vRAM369)**, sobre el trabajo original de [James Kokoska](https://github.com/jameskokoska) y colaboradores de Allowance. Contacto: [d4vram369@proton.me](mailto:d4vram369@proton.me) · [Telegram](https://t.me/D4vRAM369).

[![Buy Me a Coffee](https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=☕&slug=D4vRAM369&button_colour=5F7FFF&font_colour=ffffff&font_family=Inter&outline_colour=000000&coffee_colour=FFDD00)](https://www.buymeacoffee.com/D4vRAM369)

Si te gusta la base, apoya también al autor original: [ko-fi.com/dapperappdeveloper](https://ko-fi.com/dapperappdeveloper).

## Qué añade

- **Bloqueo de la app:** PIN de 6–8 dígitos (solo se guarda un hash Argon2id), huella del sistema y bloqueo automático al salir (inmediato, 30 s, 1 min o 5 min). Espera creciente tras 5 fallos.
- **Ocultar importes:** botón de ojo en la pantalla principal y ajuste para mostrar `••••` al abrir. Los cálculos y la base de datos no cambian.
- **Pantalla protegida:** miniatura oculta en apps recientes (Android 13+, activo por defecto) y bloqueo opcional de capturas (FLAG_SECURE).
- **Sin red:** la versión release no tiene permiso `INTERNET` ni telemetría. Se retiraron compras, reseñas y promociones heredadas.
- **Tus datos, en tus archivos:** CSV de movimientos, backup completo cifrado con contraseña (AES-256-GCM + Argon2id) y AutoBackup cifrado a la carpeta que elijas. Excluido del backup en la nube de Android.
- **Editar descripciones** de movimientos sin tocar importes ni fechas.

Todo está en Ajustes → *Privacidad y seguridad* y *Copias y datos*.

## Límites conocidos

- La base de datos local no está cifrada: el bloqueo protege contra quien coge el móvil desbloqueado, no contra un dispositivo con root.
- Si olvidas el PIN y no tienes la huella activada, no hay recuperación: solo tus copias de seguridad. Si pierdes la contraseña de una copia, no se puede descifrar.
- Una huella nueva añadida al sistema también desbloquea la app.

## Compilar

Flutter 3.19.6 (Dart 3.3.4), Android SDK 34 y JDK 17.

```bash
cd budget_simple
flutter pub get
flutter test
cd android
JAVA_HOME=/ruta/al/jdk17 ./gradlew assembleDebug
```

`flutter build` puede elegir el JDK de Android Studio, incompatible con Gradle 7.5; por eso se usa `gradlew` con JDK 17. Para release, crea tu propio `android/key.properties` y keystore (ignorados por Git).

El README original de Allowance sigue a continuación; sus enlaces y capturas pertenecen al proyecto original.

---

<h1 align="center" style="font-size:28px; line-height:1"><b>Allowance</b></h1>

<a href="https://allowance-track.web.app/">
  <div align="center">
    <img alt="Icon" src="promotional/README/icon.png" width="150px">
  </div>
</a>

<br />

<div align="center">
  <a href="https://apps.apple.com/us/app/allowance/id6463812712">
    <img alt="iOS App Store Badge" src="promotional/README/app-store-badge.png" height="60px">
  </a>
  <a href="https://play.google.com/store/apps/details?id=com.budget.allowance">
    <img alt="Google Play Badge" src="promotional/README/google-play-badge.png" height="60px">
  </a>
  <a href="https://github.com/jameskokoska/Allowance/releases/">
    <img alt="GitHub Badge" src="promotional/README/github-badge.png" height="60px">
  </a>
  <a href="https://allowance-track.web.app/">
    <img alt="PWA Badge" src="promotional/README/pwa-badge.png" height="60px">
  </a>
</div>

<br />


## Overview
Allowance uses a calculator-like interface to let you track your spending habits in a unique and simple way. Discover a budget that works for you and narrow down extra spending habits. It is built using Flutter, Dart, and SQL.

## Featured
Allowance was featured on [YouTube](https://www.youtube.com/watch?v=uwY6-5CHj44&t=336s)!
Thanks [Sam Beckman](https://www.youtube.com/@sambeckman)!

<a href="https://www.youtube.com/watch?v=uwY6-5CHj44&t=336s">
  <div align="center">
    <img width="80%" src="promotional/README/review-video-thumbnail.png" alt="Review Video">
  </div>
</a>

<br>

| ![Screenshot 1](promotional/PlayStore/Frame1.png) | ![Screenshot 2](promotional/PlayStore/Frame2.png) | ![Screenshot 3](promotional/PlayStore/Frame3.png) |
| ------------- | ------------- | ------------- |
| ![Screenshot 4](promotional/PlayStore/Frame4.png) | ![Screenshot 5](promotional/PlayStore/Frame5.png) |  |


## Features
- Set a spending goal for a given period of time
- Track transactions and see how much you have left to spend
- Readjust your budget at the end of each period
- Material You theming with custom accent colors

## Usage
To use the app, simply set a spending goal and track your transactions. You can readjust your budget at the end of each period to ensure you're on track with your financial goals.

## Technologies
* [Flutter](https://flutter.dev/) (v3.19.6)
* [Dart](https://dart.dev/)
* [SQL](https://drift.simonbinder.eu/)

## Releases
### iOS: App Store
An App Store release is available at https://apps.apple.com/us/app/allowance/id6463812712
### Android: Google Play
A Google Play release is available at https://play.google.com/store/apps/details?id=com.budget.allowance
### GitHub: Android
The open source GitHub release for Android is available at https://github.com/jameskokoska/Allowance/releases/
### Web App
A web app version of Allowance is available at https://allowance-track.web.app/

## Supported Languages
Allowance is currently available in the following languages:

- English
- French
- Spanish
- Chinese (Simplified)
- Hindi
- Arabic
- Portuguese
- Russian
- Japanese
- German
- Korean
- Turkish
- Italian
- Vietnamese
- Polish
- Dutch
- Thai
- Czech
