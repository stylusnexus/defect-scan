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

## Reasoning checklist
Baseline categories specialized:
- cat#1: non-null assertion `!` on a nullable that can be null; `late` fields read
  before init; force-unwrap of `Map[...]`/`firstWhere` with no `orElse`.
- cat#2: empty `catch {}` / `on X catch (_) {}` that swallows; ignored `Future`
  errors; `print`-and-continue on a real failure.
- cat#3: unsanitized input into `Uri`/SQL/`Process.run`/WebView `loadHtmlString`;
  `dangerouslySetInnerHTML`-equivalents in embedded web.
- cat#4: `StreamSubscription`, `AnimationController`, `TextEditingController`,
  `Timer`, `FocusNode` created but not `dispose()`d / `cancel()`d in `dispose()`.
- cat#5: `async`/await gaps — see Flutter-specific.
Flutter/Dart-specific:
- **`BuildContext` across an async gap** — using `context` after an `await`
  without a `mounted` check (the #1 Flutter footgun; analyzer flags
  `use_build_context_synchronously`).
- **`setState` after dispose** — calling `setState`/using `context` once the
  widget is unmounted.
- **Unawaited futures** — fire-and-forget `Future`s that drop errors
  (`unawaited_futures`); missing `await` on a side-effecting call.
- **Provider/Bloc misuse** — `watch` in callbacks, building controllers in
  `build()` (recreated every frame).
- Equality/`hashCode` mismatch on value types; `==` on mutable models.

## Auto-fix-safe
Only `dart fix --apply`-style analyzer fixes for lints in a safe set
(unused-import, prefer-const, formatting via `dart format`). NOT auto-safe:
`use_build_context_synchronously`, null-safety changes, dispose insertions —
these change behavior; list them for human review.
