#!/usr/bin/env sh
# defect-scan — one-liner setup for the OPTIONAL deep analyzers.
# Best-effort: installs what your available package managers support, skips the
# rest. The scan works without these; they just add ground-truth coverage
# (semgrep → injection/subprocess/SQL, gitleaks → secrets, bandit/pip-audit →
# Python security + vuln deps, osv-scanner → cross-ecosystem vuln deps).
#
# Usage:  sh scripts/setup-optional-tools.sh
set -u
have() { command -v "$1" >/dev/null 2>&1; }
echo "defect-scan: installing optional analyzers (best-effort)…"

if have brew; then
  echo "→ brew: semgrep gitleaks osv-scanner"
  brew install semgrep gitleaks osv-scanner 2>/dev/null || true
fi

if have pipx; then
  echo "→ pipx: semgrep bandit pip-audit"
  for p in semgrep bandit pip-audit; do pipx install "$p" 2>/dev/null || true; done
elif have pip3 || have pip; then
  PIP="$(command -v pip3 || command -v pip)"
  echo "→ $PIP --user: semgrep bandit pip-audit"
  "$PIP" install --user semgrep bandit pip-audit 2>/dev/null || true
fi

echo
echo "resolved analyzers:"
for t in semgrep gitleaks bandit pip-audit osv-scanner; do
  printf '  %-12s %s\n' "$t" "$(command -v "$t" 2>/dev/null || echo 'not installed')"
done
echo
echo "Done. Re-run /defect-scan:scan to use whatever installed."
