---
name: java
detect_files: pom.xml build.gradle build.gradle.kts settings.gradle settings.gradle.kts gradlew
extensions: java gradle
tools: spotbugs pmd dependency-check
---
# Profile: java

## Detection
A `pom.xml` (Maven) or `build.gradle`/`build.gradle.kts` (Gradle), corroborated by
`settings.gradle(.kts)` / `gradlew`, plus any `*.java`. The Java release
(`<maven.compiler.release>` / `sourceCompatibility`) gates a few rules (records, sealed
classes, `var`). See `detect.sh stacks`.

## Toolchain
Resolve each via `detect.sh tool <name>`. **Most Java analyzers need the project to
COMPILE** — SpotBugs reads `.class` bytecode, Error Prone is a javac plugin,
dependency-check needs resolved deps. Only PMD/Checkstyle are source-only. On a tree
that won't build (no network/missing deps) the bytecode/compile tools degrade —
skip-with-hint. Ordered by value:
- **Error Prone (+ NullAway)** — compile-time bug patterns via the Maven compiler
  plugin / Gradle `net.ltgt.errorprone`. ~500 patterns (`CheckReturnValue`,
  `EqualsHashCode`, `ReferenceEquality`, `DefaultCharset`); NullAway adds dataflow
  nullness. Output is compiler diagnostics (parse the build log; patch mode
  `-XepPatchChecks:`). Runs *through the build*, not as a standalone binary.
- `spotbugs -sarif -pluginList findsecbugs-plugin.jar <classesdir>` (or the Maven/
  Gradle plugin with `sarifOutput`/`reports{sarif}`) — bytecode analysis;
  **find-sec-bugs** adds security taint (SQLi, injection, deserialization, XXE, crypto).
  Needs compiled `.class`. Install: SpotBugs + find-sec-bugs plugin.
- `pmd check -R rulesets/java/quickstart.xml -f sarif -d <src>` — source AST rules
  (the only tool that works on a non-building tree). Covers errorprone/bestpractices/
  design/multithreading. Install: PMD 7.
- `dependency-check` (`mvn org.owasp:dependency-check-maven:check` / `gradle
  dependencyCheckAnalyze`) — known-vuln (CVE) deps; needs resolved deps + NVD data;
  High; never auto-fixed.
- `checkstyle` — style (low defect value; mention only).

## Reasoning checklist
Baseline categories specialized:
- cat#1: dereferencing a nullable return without a guard (SpotBugs
  `NP_NULL_ON_SOME_PATH(_FROM_RETURN_VALUE)`, NullAway, CWE-476); `Optional` misuse
  (`.get()` without `isPresent()`); **autoboxing NPE** — unboxing a `null`
  `Integer`/`Long`/`Boolean` into a primitive (SpotBugs `NP_*`/`BX_*`).
- cat#2: empty/swallowing `catch (Exception e) {}` (PMD `EmptyCatchBlock`, CWE-390);
  catching `Throwable`/`Error` (masks `OutOfMemoryError`); **swallowing
  `InterruptedException`** without `Thread.currentThread().interrupt()` or rethrow
  (CERT THI05-J); `printStackTrace()` as the only handling.
- cat#3: SQL injection — `Statement` + string concat vs `PreparedStatement`
  (find-sec-bugs `SQL_INJECTION*`, CWE-89); command injection — `Runtime.exec`/
  `ProcessBuilder` with untrusted input (`COMMAND_INJECTION`, CWE-78); unsafe
  deserialization — `ObjectInputStream.readObject` on untrusted data
  (`OBJECT_DESERIALIZATION`, CWE-502); XXE — `DocumentBuilderFactory`/`SAXParserFactory`/
  `XMLInputFactory`/`TransformerFactory` without disabling DTDs/external entities
  (`XXE_*`, CWE-611); path traversal (`PT_*`, CWE-22); weak crypto MD5/SHA-1/DES/ECB
  (`WEAK_MESSAGE_DIGEST_*`/`ECB_MODE`, CWE-327); `java.util.Random`/`Math.random()` for
  tokens vs `SecureRandom` (`PREDICTABLE_RANDOM`, CWE-330).
- cat#4: `InputStream`/`Reader`/`Connection`/`Statement`/`ResultSet` not closed on all
  paths — missing **try-with-resources** (SpotBugs `OS_OPEN_STREAM(_EXCEPTION_PATH)`,
  `OBL_UNSATISFIED_OBLIGATION`, `ODR_OPEN_DATABASE_RESOURCE`, CWE-404/772); closed only
  on the happy path / in a `finally` that can itself throw.
- cat#5: inconsistent synchronization — field written under `synchronized`, read without
  (SpotBugs `IS2_INCONSISTENT_SYNC`, CWE-362); broken double-checked locking
  (`LI_LAZY_INIT_STATIC`, `DC_DOUBLECHECK`); **`SimpleDateFormat`/`Calendar` shared
  across threads** (not thread-safe — `STCAL_*`); non-atomic check-then-act; `volatile`
  misused as if it gave compound-op atomicity.
Java-specific: reference equality — `==` on `String`/boxed types instead of `.equals()`
(SpotBugs `ES_COMPARING_STRINGS_WITH_EQ`/`RC_REF_COMPARISON`; Error Prone
`ReferenceEquality`); `equals`/`hashCode` contract — overriding one not the other
(SpotBugs `HE_*`; Error Prone `EqualsHashCode`); exposing internal representation —
returning/storing a mutable field (array/`Date`/collection) without a defensive copy
(`EI_EXPOSE_REP(2)`, CWE-374/375); ignored return value of a must-use method
(`RV_RETURN_VALUE_IGNORED*`; Error Prone `CheckReturnValue`, CWE-252); platform-default
charset — `new String(bytes)`/`FileReader` without an explicit charset (Error Prone
`DefaultCharset`); integer overflow / int-division-where-double-intended (`ICAST_*`,
CWE-190).

## Auto-fix-safe
Only formatting — `spotless:apply` / `spotlessApply` / `google-java-format` (whitespace
+ import ordering, no semantic change). **Never auto-fix**: all find-sec-bugs findings
(security), SpotBugs correctness/concurrency (`NP_*`/`OS_OPEN_STREAM`/`IS2_*`/
`EI_EXPOSE_REP`/`RV_*` — closing a borrowed stream or adding a defensive copy changes
ownership/semantics), PMD `EmptyCatchBlock`/design rules, and dependency-check CVE
results (a dependency bump needs human review + tests). Error Prone `-XepPatchChecks`
exists but is opt-in/advisory — safe only for cosmetic checks (`MissingOverride`,
`RemoveUnusedImports`), never the bug-finding ones.
