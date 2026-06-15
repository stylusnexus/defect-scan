---
name: php
detect_files: composer.json composer.lock
extensions: php
tools: phpstan psalm composer-audit
---
# Profile: php

## Detection
A `composer.json`/`composer.lock`, or any `*.php`. A `composer.json` requiring
`laravel/framework`/`symfony/*` (or `artisan`/`bin/console`) means treat as a framework
app — enables framework stubs for Psalm taint and routes XSS/SQLi through the
framework's escaping/query layer. See `detect.sh stacks`.

## Toolchain
Resolve each via `detect.sh tool <name>`. **Autoload matters:** PHPStan/Psalm load the
project autoloader/classmap to resolve types — without `vendor/autoload.php` (no
`composer install`) they degrade badly; run `composer install` first or skip-with-hint.
`composer audit` is the inverse — needs only `composer.lock`.
- `vendor/bin/phpstan analyse --error-format=json --no-progress <paths>` — deep type/
  correctness engine. Levels 0–9/`max` (`--level=max`); ratchet up. Pass
  `--autoload-file vendor/autoload.php`. Catches undefined vars/array keys, null access,
  wrong arg/return types, dead code. Install: `composer require --dev phpstan/phpstan`
  (Laravel: `larastan/larastan`; Symfony: `phpstan/phpstan-symfony`).
- `vendor/bin/psalm --output-format=json --no-progress` — second type engine; its
  differentiator is **taint analysis**: `psalm --taint-analysis` traces untrusted
  sources → sinks, emitting `TaintedSql`/`TaintedHtml`/`TaintedShell`/`TaintedInclude`/
  `TaintedUnserialize`. **Caveat:** taint already treats `$_GET`/`$_POST`/`$_COOKIE` as
  sources out of the box; `@psalm-taint-*` annotations or framework stubs
  (`psalm/plugin-laravel`/`-symfony`) are needed for *framework* request sources
  (request objects, route params) and to model the ORM/escapers as sanitizers — code
  that wraps input behind a framework request layer underreports without them. Install:
  `composer require --dev vimeo/psalm`.
- `composer audit --format=json` — known-vuln deps from the Packagist advisories DB;
  reads `composer.lock`; built into Composer 2.4+; High. Never auto-fixed.
- `vendor/bin/phpcs --report=json` — PSR-12 style (low defect value; its `phpcbf` fixer
  is the safe auto-fixer). Mention only.

## Reasoning checklist
Baseline categories specialized (PHPStan/Psalm/CWE). Note **cat#5 concurrency is mostly
N/A** for share-nothing PHP-FPM — scope it to long-running workers (Swoole/RoadRunner/
ReactPHP, `pcntl` forks, shared APCu/session state).
- cat#3: **SQL injection** — interpolated queries (`"… WHERE id = $id"`, `DB::raw("… $x")`)
  vs PDO/mysqli prepared statements with bound params (Psalm `TaintedSql`, CWE-89);
  **command injection** — untrusted input into `exec`/`system`/`shell_exec`/`passthru`/
  `proc_open`/backticks without `escapeshellarg` (`TaintedShell`, CWE-78); **XSS** —
  unescaped `echo`/`print`, Blade `{!! !!}`, Twig `|raw` on user input vs auto-escaped
  output (`TaintedHtml`, CWE-79); **`unserialize()` on untrusted data** — object
  injection / POP-chain RCE; prefer `json_decode` or `['allowed_classes' => false]`
  (CWE-502); **`include`/`require` with user input** — LFI/RFI (CWE-98/22); **path
  traversal** — untrusted path into `fopen`/`file_get_contents`/`readfile` without
  `realpath` + base-dir containment (CWE-22); **`extract()`/variable variables `$$x`/
  mass assignment** — `extract($_REQUEST)`, unguarded `Model::fill($request->all())`
  (CWE-915/621); **weak crypto / predictable randomness** — `md5`/`sha1` for passwords
  vs `password_hash`; `mt_rand`/`rand`/`uniqid` for tokens vs `random_bytes`/`random_int`
  (CWE-327/328/338).
- cat#2: **`@` error suppression** (`@file_get_contents(...)`, `@$arr['k']`) silently
  swallows warnings/errors (PHP-specific footgun, CWE-390); empty/log-only
  `catch (\Throwable $e) {}` with no rethrow.
- cat#1: **undefined array key** `$arr['k']` on a missing key (E_WARNING since PHP 8),
  and `$obj->prop`/`$obj->method()` on `null` (PHPStan `offsetAccess.notFound`/
  `property.nonObject`/`method.nonObject`; CWE-476/252).
- PHP-specific: **loose `==` vs strict `===`** (type juggling) — `"0e123" == "0e456"`
  both coerce to `0` (magic-hash collision when comparing hashes), `0 == "abc"` true
  pre-PHP 8, loose `in_array`/`switch`; use `===`/`hash_equals`/`in_array(…, true)` —
  auth-bypass/logic class (CWE-697); **missing `declare(strict_types=1)`** — scalar type
  hints silently coerce (`"5abc"`→`5`, `null`→`0`), hiding bad input.
- Framework apps: mass-assignment via `$guarded = []`; serializer/`toArray`/`$hidden`
  leaking `password`/tokens (CWE-200); missing `@csrf` on state-changing forms (CWE-352).

## Auto-fix-safe
Only `vendor/bin/phpcbf` (PSR-12 whitespace/layout) and Rector/Psalm `--alter` cosmetic
fixes (docblock/return-type additions). **Never auto-fix**: all PHPStan/Psalm correctness
findings, every Psalm **taint** finding, `==`→`===` rewrites (changes comparison
semantics — human call), unserialize/include/crypto/randomness findings, and all
`composer audit` vuln-dep results (a dependency bump needs review + tests).
