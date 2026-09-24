# Release signing

Upload/release keystore lives **outside** git:

- Keystore: `/workspace/secrets/ssh-pad-upload.jks` (or your own path)
- Properties: `/workspace/secrets/key.properties`

`android/app/build.gradle.kts` reads `key.properties` when present; otherwise
release falls back to the Android **debug** keystore (fine for local smoke tests).

## Generate your own key

```bash
mkdir -p /workspace/secrets
keytool -genkeypair -v -keystore /workspace/secrets/ssh-pad-upload.jks \
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias ssh-pad \
  -storepass 'YOUR_STORE_PASS' -keypass 'YOUR_KEY_PASS' \
  -dname "CN=SSH Pad, OU=Dev, O=You, L=City, ST=ST, C=US"

cat > /workspace/secrets/key.properties <<'PROP'
storePassword=YOUR_STORE_PASS
keyPassword=YOUR_KEY_PASS
keyAlias=ssh-pad
storeFile=/workspace/secrets/ssh-pad-upload.jks
PROP
```

## Build

```bash
export PATH="/home/box/flutter/bin:$PATH"
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
flutter build apk --debug
```

Never commit `*.jks`, `key.properties`, or `*.apk`.
