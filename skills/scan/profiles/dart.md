---
name: dart
detect_files: pubspec.yaml
extensions: dart
tools: dart flutter
---
# Profile: dart (Flutter)

## Detection
`pubspec.yaml` or any `*.dart`. See `detect.sh stacks`.

## Toolchain
Resolve each via `detect.sh tool <name>` (then global). Run from the package root
(where `pubspec.yaml` lives). Skip-with-hint if unresolved.
- `dart analyze --format=machine <dir>`       — analyzer diagnostics (errors,
  warnings, lints from `analysis_options.yaml`). Tool-confirmed → High.
- `flutter analyze` (if a Flutter app)         — same analyzer, Flutter-aware.
Exit codes: `0` clean; non-zero = diagnostics found (parse them) OR a tool error
(no package / bad config) → inconclusive, not clean.
Install hints: install the Flutter/Dart SDK (`dart`/`flutter` on PATH).

**The highest-value leak/async lints are opt-in and absent from `flutter_lints`.** The
default set enables `use_build_context_synchronously`,
`prefer_const_constructors_in_immutables`, `avoid_print`, `use_key_in_widget_constructors`,
`prefer_final_fields` — but **`unawaited_futures`, `discarded_futures`,
`cancel_subscriptions`, `close_sinks`, `avoid_dynamic_calls`, and `prefer_const_constructors`
are NOT on by default**. On a repo without them in `analysis_options.yaml` those footguns
are invisible to the tool — the reasoning pass must catch them; to max out tool coverage,
enable the fuller set (`package:lints/all.yaml`-style) and re-run `dart analyze`.

## Reasoning checklist
Baseline categories specialized:
- cat#1: non-null assertion `!` on a nullable that can be null; `late` fields read
  before init; force-unwrap of `Map[...]`/`firstWhere` with no `orElse` (StateError);
  method/property access on a `dynamic` target (`avoid_dynamic_calls`,
  runtime `NoSuchMethodError`).
- cat#2: empty `catch {}` / `on X catch (_) {}` that swallows; ignored `Future`
  errors; `print`-and-continue on a real failure (`avoid_print` in prod); swallowing
  inside `Future.catchError(...)`/`.then(onError:)` returning a fallback (the async
  empty-catch); **no top-level async error boundary** (`FlutterError.onError` /
  `PlatformDispatcher.instance.onError` / `runZonedGuarded` absent → prod errors vanish).
- cat#3: unsanitized input into `Uri`/SQL/`Process.run`/WebView `loadHtmlString`;
  **TLS validation disabled** — `badCertificateCallback = (c,h,p) => true` (MITM,
  CWE-295); **sensitive data in `SharedPreferences`/plain files** vs
  `flutter_secure_storage` (cleartext, CWE-312); hardcoded secrets / `http://`
  endpoints shipped in the APK/IPA (CWE-798/319); `WebView` `javascriptMode:
  unrestricted` + file access (`allowUniversalAccessFromFileURLs`) → local-file
  exfiltration (CWE-749).
- cat#4: `StreamSubscription`, `AnimationController`, `TextEditingController`, `Timer`,
  `FocusNode`, **`ScrollController`/`PageController`/`TabController`** created but not
  `dispose()`d/`cancel()`d in `dispose()`; **`addListener`/`WidgetsBinding.addObserver`/
  `ChangeNotifier` listeners added without the matching `removeListener`/`removeObserver`**
  (fires after unmount; `cancel_subscriptions`/`close_sinks` catch the stream cases when
  enabled; CWE-401).
- cat#5: heavy CPU work (large JSON decode, image/crypto, sorting) on the **main
  isolate** → dropped frames; use `compute()`/`Isolate` (jank); `setState()` called
  during `build()` (throws "setState called during build"); serial `await` in a loop
  over independent I/O where `Future.wait` would parallelize.
Flutter/Dart-specific:
- **`BuildContext` across an async gap** — `context` after an `await` without a
  `mounted` check (the #1 Flutter footgun; `use_build_context_synchronously`).
- **`setState` after dispose** — `setState`/`context` once the widget is unmounted.
- **Unawaited / discarded futures** — fire-and-forget `Future`s that drop errors;
  `unawaited_futures` fires in `async` bodies, **`discarded_futures`** covers the
  *synchronous* contexts (constructors, callbacks, getters) it misses.
- **Work created inside `build()`** — controllers/listeners/`Future`s/`Stream`s built in
  `build()` are recreated every frame (leak + lost state + perf); hoist to `initState`/
  `didChangeDependencies`. Generalizes the Provider/Bloc case to all controllers.
- **Missing `const` constructors** — non-`const` widgets rebuild every frame
  (`prefer_const_constructors`/`prefer_const_constructors_in_immutables`; perf).
- **Missing `Key` on stateful list items** — element recycling matches by type+position,
  so on reorder/insert state (scroll offset, `TextField` text) attaches to the wrong
  item; use `ValueKey`/`ObjectKey`.
- **Provider/Bloc misuse** — `watch` in callbacks, controllers built in `build()`.
- Equality/`hashCode` mismatch on value types; `==` on mutable models;
  private fields never reassigned not marked `final` (`prefer_final_fields`).

## Auto-fix-safe
Only `dart fix --apply`-style analyzer fixes in a safe set: `unused_import`,
`prefer_const_*`, `prefer_final_fields`, `avoid_print` (to a logger), and formatting via
`dart format`. **NOT auto-safe**: `use_build_context_synchronously`, null-safety changes,
`dispose`/`removeListener` insertions, `discarded_futures`/`unawaited_futures` (adding
`await` vs `unawaited()` changes semantics), TLS/secure-storage/WebView security fixes —
all change behavior; list them for human review.
