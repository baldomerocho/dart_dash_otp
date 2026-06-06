# Revisión 1 — dart_dash_otp

Rama: `analisis/rev1`
Versión revisada: `1.3.4` (pubspec.yaml)
Alcance: `lib/`, `test/`, `example/`, `pubspec.yaml`, `README.md`, `CHANGELOG.md`.

## Resumen

El plugin funciona y los tests pasan el happy path, pero el código está estancado en Dart 2.12, tiene deuda técnica en correctitud de tiempo, construcción de URLs otpauth y verificación de OTP. Hay APIs con tipos nullable innecesarios, asserts que no aplican en release, y cero vectores de prueba del RFC. No es production-grade para un autenticador serio.

---

## Problemas críticos (correctitud / seguridad)

### 1. `Util.timeFormat` usa `substring` sobre el epoch en ms
`lib/src/utils/generic_util.dart:16-21`. Convierte de ms a segundos recortando los últimos 3 caracteres de la representación en string. Falla para fechas anteriores al epoch (ms negativos) y es O(n) por alocación de string donde debería ser una división entera. Reemplazar por:
```dart
return time.millisecondsSinceEpoch ~/ 1000 ~/ interval;
```

### 2. `Util.intToBytelist` confunde `padding` con tamaño de buffer y shift
`lib/src/utils/generic_util.dart:32-46`. El parámetro `padding` se usa a la vez como:
- Longitud en bytes del buffer de salida.
- Magnitud del desplazamiento binario (`_input >>= padding`).

El HOTP/TOTP (RFC 4226) requiere un counter de 8 bytes big-endian, desplazando 8 bits por byte. Si alguien pasa `padding: 6`, se obtiene una lista de 6 bytes con shift de 6 bits — no es serialización big-endian válida. El test `generic_util_test.dart:24` solo valida `length`, nunca el contenido. Esta función es semánticamente incorrecta salvo en el caso default. Cambiar por un shift fijo de 8 bits y recibir `byteCount` por separado, o mejor usar `ByteData.setUint64`.

### 3. Verificación OTP sin ventana de tolerancia
`lib/src/totp.dart:93-103` y `lib/src/hotp.dart:71-78`. `verify` solo compara contra el intervalo/contador exacto. Todas las libs serias (pyotp, otplib, speakeasy) aceptan `window` (p.ej. ±1 intervalo para skew de reloj, counter+N para HOTP). Sin esto, el usuario real falla al autenticar cuando su reloj desviado por 2 segundos cruza un boundary de 30s.

### 4. Comparación no constant-time en `verify`
`lib/src/totp.dart:102` y `lib/src/hotp.dart:77`. Usa `otp == otpTime` con `String`. En Dart esa comparación hace shortcut por longitud y por chars — es vulnerable a timing attacks. En OTP el riesgo práctico es bajo (6-8 dígitos y ventanas cortas), pero una lib de seguridad debe usar comparación constant-time.

### 5. `generateOTP` usa bang-operator sobre el HMAC
`lib/src/otp.dart:59-62`. `AlgorithmUtil.createHmacFor(...)!`. El método devuelve `null` si el key es nulo o el algoritmo no matchea. Si en algún momento se añade un algoritmo y se olvida actualizar el switch, el código revienta en producción con un `Null check operator`. Devolver non-null por diseño (no permitir `OTPAlgorithm?` nulos en esa API).

### 6. URL `otpauth://` no cumple con el formato Key URI de Google
`lib/src/otp.dart:89-99`. Problemas:
- El label debería ser `Issuer:Account` según [Key URI Format](https://github.com/google/google-authenticator/wiki/Key-Uri-Format). Aquí solo se pone `Account`, e `issuer` solo va en query. Google Authenticator / Authy pueden mostrar el token sin issuer en la UI.
- `secret` no se URL-encodea.
- `account` se codifica con `Uri.encodeComponent` pero `issuer` con `Uri.encodeQueryComponent` — dos codificaciones distintas sin razón.
- Si `extraUrlProperties` estuviera vacío, la URL termina con `&` colgando (hoy no se da porque HOTP y TOTP siempre agregan `counter`/`period`, pero el diseño es frágil).
- No hay validación de que `secret` sea base32 válido antes de construir la URL.

---

## Problemas de diseño de API

### 7. Campos mutables donde deberían ser `final`
`lib/src/otp.dart:16-22`. `digits`, `secret`, `algorithm` son públicos y mutables. Un consumidor puede mutar `secret` en runtime y romper la correspondencia con la URL emitida. Deben ser `final`.

### 8. `assert` para validación de `digits`
`lib/src/otp.dart:41`. El `assert(digits >= 6 && digits <= 8)` solo corre en debug. En release se puede construir `OTP(secret: "X", digits: 12)` sin ruido. Usar `ArgumentError.checkNotNull` / `RangeError.checkValueInInterval`.

### 9. `TOTP.interval` es nullable pero jamás puede ser null
`lib/src/totp.dart:15, 41`. Declarado `int?`, inicializado siempre en el constructor con un default, y luego se usa con `interval!` en tres lugares. Tipado defensivo innecesario. Hacerlo `final int interval`.

### 10. `HOTP.at({int? counter})` con retorno nullable por diseño defensivo
`lib/src/hotp.dart:49-55`. La clase tiene `counter` no-nullable, pero el método acepta `counter` nullable y retorna `null` si es negativo. Mezcla dos responsabilidades: lookup y validación. Mejor: método no-nullable que lance `ArgumentError` o `at()` sin parámetro que use `this.counter`.

### 11. Naming contra el style guide de Dart
- `OTPAlgorithm.SHA1` / `SHA256` / `SHA384` / `SHA512`: enums en UPPER_SNAKE. El style guide de Dart dice `lowerCamelCase` (`sha1`). Este cambio rompería la API, pero es deuda real.
- Variables locales con prefijo `_` (p.ej. `_timeStr`, `_formatTime`, `_secret`): en Dart el `_` es library-private, no convención para locals. Confunde.
- Docs en estilo JSDoc (`@param`, `@type`, `@desc`) en vez de dartdoc (`///` con markdown). `dart doc` no los renderiza.

### 12. `extraUrlProperties` devuelve `Map<String, dynamic>` y luego se stringifica sin escape
`lib/src/otp.dart:96`. Si alguien extiende `OTP` y mete un valor con `&` o `=`, la URL se corrompe. Los valores deberían pasar por `Uri.encodeQueryComponent`.

---

## Compatibilidad y entorno

### 13. SDK constraint obsoleto
`pubspec.yaml:7`: `sdk: ">=2.12.0 <3.0.0"`. Dart 3 lleva ~2 años. El paquete como publicado **no** soporta Dart 3. En pub.dev aparecerá como incompatible con cualquier proyecto moderno. Subir a `>=2.17.0 <4.0.0` o `^3.0.0` según lo que realmente necesite.

### 14. Versión inconsistente entre pubspec y README
`pubspec.yaml` dice `1.3.4`. `README.md:28` instruye instalar `^1.3.2`. Pequeño pero refleja falta de release discipline.

### 15. CHANGELOG incompleto
`CHANGELOG.md` no registra 1.3.4 con granularidad útil: "Upgrade / Update dependencies / Update documentation". No permite auditar qué cambió.

---

## Tests

### 16. Sin vectores del RFC 6238 / RFC 4226
`test/totp_test.dart`, `test/hotp_test.dart`. Los RFC vienen con vectores de prueba canónicos (timestamps y OTPs esperados para SHA1/256/512). No están. Es la forma estándar de validar la implementación. Hoy un bug en la mezcla de bytes podría pasar los tests porque solo se compara "produce algún string no nulo" o "produce el mismo valor que produjo hace 5 segundos".

### 17. `timeFormat` depende de `DateTime.now()` en tests
`test/totp_test.dart:54-58`. Cambiar `DateTime.now()` por valores fijos o inyectar un `Clock`. Los tests son flaky en el boundary del intervalo.

### 18. `intToBytelist` test no valida bytes
`test/utils/generic_util_test.dart:19-27`. Solo `length`. Agregar expectativas de contenido (big-endian del counter).

### 19. Cobertura sobre verificaciones fallidas es superficial
Solo chequea que `null` retorne `false`. No cubre: secret inválido base32, digits fuera de rango, timestamps extremos, counters muy grandes (>= 2^53 cerca del límite de int en JS compile target).

---

## Hygiene del repo

- `.DS_Store` en el working tree (en `.gitignore`, bien), pero hay uno en el tree del zip inicial.
- `example/example.dart` es un `main` suelto. Para pub.dev suma puntos tener un ejemplo más demostrativo (verify, URL generation, QR).
- Sin CI visible en la raíz (hay `.github/` pero no revisado aquí).
- Sin `analysis_options.yaml` — se usan defaults de `package:lints/recommended.yaml` o nada. Agregar `package:lints` o `package:very_good_analysis`.

---

## Priorización sugerida

1. Critical (bloqueantes de correctitud): 1, 2, 5, 6. Arreglar antes de próximo release.
2. Seguridad: 3, 4.
3. Soporte Dart 3: 13.
4. API / tipos: 7, 8, 9, 10, 12.
5. Tests: 16, 17, 18, 19.
6. Cosmético / estilo: 11, 14, 15, resto.

## Qué NO tocar

- `crypto` y `base32` como deps: ambas vivas, mantenidas, correctas.
- Estructura de archivos (`src/components`, `src/utils`): está bien separada.
- Separación HOTP / TOTP sobre `OTP` abstracto: correcto.
