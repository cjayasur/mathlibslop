#!/usr/bin/env bash
# ============================================================================
# mathlibslop verify.sh  —  the soundness GATE for the verified-proof archive.
#
# A proof is CERTIFIED iff:
#   (1) it builds/elaborates with no errors, AND
#   (2) EVERY claimed result's `#print axioms` set is a subset of the
#       allow-list (default: the 3 standard Lean axioms).
#
# Why the axiom check is the WHOLE gate (not a grep):
#   - a `sorry`        => shows up as axiom `sorryAx`
#   - an `admit`       => `sorryAx`
#   - a `native_decide`=> axiom `Lean.ofReduceBool` (compiler-trusted, NOT sound-pure)
#   - any custom `axiom`=> shows up by its own name
#   All of these APPEAR in `#print axioms`. So an allow-list of exactly
#   {propext, Classical.choice, Quot.sound} rejects every known cheat.
#
# Modes:
#   --project DIR   certify a Lake project (runs `lake env lean` for axioms)
#   --file   FILE   certify a single standalone .lean file (runs `lean`)
#
# Usage:
#   ./verify.sh --name alpoge-riemann \
#       --project /home/cjayasur/lean-riemann/lean \
#       --result Main:riemannHypothesis \
#       --result Main:riemannZeta_eq_zero_re
#
#   ./verify.sh --name selftest --file /tmp/t.lean --result _:good
#       (Module "_" means: results live in the file itself, no import needed)
# ============================================================================
set -u

ALLOW="propext,Classical.choice,Quot.sound"
PROJECT=""
FILE=""
NAME="entry"
NO_BUILD=0
declare -a RESULTS=()
LAKE=""
LEAN=""
OUTDIR="$(cd "$(dirname "$0")" && pwd)/certs"

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2;;
    --file)    FILE="$2"; shift 2;;
    --result)  RESULTS+=("$2"); shift 2;;
    --allow)   ALLOW="$2"; shift 2;;
    --name)    NAME="$2"; shift 2;;
    --no-build) NO_BUILD=1; shift;;
    --out)     OUTDIR="$2"; shift 2;;
    --lake)    LAKE="$2"; shift 2;;
    --lean)    LEAN="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

# --- locate the toolchain -----------------------------------------------------
[ -z "$LAKE" ] && LAKE="$(command -v lake || echo "$HOME/.elan/bin/lake")"
[ -z "$LEAN" ] && LEAN="$(command -v lean || echo "$HOME/.elan/bin/lean")"

if [ ${#RESULTS[@]} -eq 0 ]; then echo "ERROR: need at least one --result MOD:THM" >&2; exit 2; fi
if [ -z "$PROJECT" ] && [ -z "$FILE" ]; then echo "ERROR: need --project or --file" >&2; exit 2; fi

mkdir -p "$OUTDIR"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
HOST="$(hostname)"
CERT="$OUTDIR/${NAME}.$(date -u +%Y%m%dT%H%M%SZ).cert.txt"

# normalise allow-list into a lookup
IFS=',' read -r -a ALLOWARR <<< "$ALLOW"
is_allowed() { local a; for a in "${ALLOWARR[@]}"; do [ "$(echo "$a"|xargs)" = "$1" ] && return 0; done; return 1; }

# --- a runner that elaborates one scratch file & prints axioms ----------------
# $1 = module (or "_" for standalone --file), $2 = theorem name
axioms_of() {
  local mod="$1" thm="$2" tmp out
  tmp="$(mktemp --suffix=.lean)"
  if [ -n "$FILE" ]; then
    # standalone: paste the file, then ask for its axioms
    { cat "$FILE"; printf '\n#print axioms %s\n' "$thm"; } > "$tmp"
    out="$("$LEAN" "$tmp" 2>&1)"
  else
    printf 'import %s\n#print axioms %s\n' "$mod" "$thm" > "$tmp"
    out="$(cd "$PROJECT" && "$LAKE" env lean "$tmp" 2>&1)"
  fi
  rm -f "$tmp"
  printf '%s' "$out"
}

echo "=== mathlibslop verify :: $NAME ===" | tee "$CERT"
{
  echo "timestamp:  $STAMP"
  echo "host:       $HOST"
  echo "mode:       ${PROJECT:+project=$PROJECT}${FILE:+file=$FILE}"
  echo "allow-list: $ALLOW"
  if [ -n "$PROJECT" ] && [ -f "$PROJECT/lean-toolchain" ]; then
    echo "toolchain:  $(cat "$PROJECT/lean-toolchain")"
  fi
  if [ -n "$PROJECT" ] && [ -d "$PROJECT/.git" ]; then
    echo "git-rev:    $(cd "$PROJECT" && git rev-parse HEAD 2>/dev/null)"
  fi
  echo
} | tee -a "$CERT"

# --- (1) build step -----------------------------------------------------------
BUILD_OK=1
if [ -n "$PROJECT" ] && [ "$NO_BUILD" -eq 0 ]; then
  echo "[build] lake build ..." | tee -a "$CERT"
  if (cd "$PROJECT" && "$LAKE" build >/tmp/slop_build.$$ 2>&1); then
    echo "[build] OK" | tee -a "$CERT"
  else
    BUILD_OK=0
    echo "[build] FAILED (tail):" | tee -a "$CERT"
    tail -5 /tmp/slop_build.$$ | sed 's/^/    /' | tee -a "$CERT"
  fi
  rm -f /tmp/slop_build.$$
else
  echo "[build] skipped (--no-build or --file)" | tee -a "$CERT"
fi
echo | tee -a "$CERT"

# --- (2) axiom gate per result ------------------------------------------------
GATE_OK=1
echo "[axioms] checking ${#RESULTS[@]} claimed result(s):" | tee -a "$CERT"
for r in "${RESULTS[@]}"; do
  mod="${r%%:*}"; thm="${r##*:}"
  out="$(axioms_of "$mod" "$thm")"
  if printf '%s' "$out" | grep -qiE 'error'; then
    GATE_OK=0
    echo "  ✖ $thm : ELABORATION ERROR" | tee -a "$CERT"
    printf '%s\n' "$out" | grep -iE 'error' | head -2 | sed 's/^/        /' | tee -a "$CERT"
    continue
  fi
  if printf '%s' "$out" | grep -q 'does not depend on any axioms'; then
    echo "  ✔ $thm : {} (no axioms) — CLEAN" | tee -a "$CERT"
    continue
  fi
  # extract the [ ... ] list
  list="$(printf '%s' "$out" | sed -n 's/.*depends on axioms:\s*\[\(.*\)\].*/\1/p')"
  if [ -z "$list" ]; then
    GATE_OK=0
    echo "  ✖ $thm : could not read axioms. raw:" | tee -a "$CERT"
    printf '%s\n' "$out" | head -3 | sed 's/^/        /' | tee -a "$CERT"
    continue
  fi
  bad=""
  IFS=',' read -r -a AX <<< "$list"
  for a in "${AX[@]}"; do a="$(echo "$a"|xargs)"; is_allowed "$a" || bad="$bad $a"; done
  if [ -z "$bad" ]; then
    echo "  ✔ $thm : [$list] — all standard" | tee -a "$CERT"
  else
    GATE_OK=0
    echo "  ✖ $thm : DISALLOWED axiom(s):$bad   (full: [$list])" | tee -a "$CERT"
  fi
done
echo | tee -a "$CERT"

# --- verdict ------------------------------------------------------------------
if [ "$BUILD_OK" -eq 1 ] && [ "$GATE_OK" -eq 1 ]; then
  VERDICT="CERTIFIED"
else
  VERDICT="REJECTED"
fi
echo "VERDICT: $VERDICT" | tee -a "$CERT"
# content hash of the certificate (tamper-evident)
HASH="$(sha256sum "$CERT" | cut -d' ' -f1)"
echo "cert-sha256: $HASH" | tee -a "$CERT"
echo
echo ">>> certificate written: $CERT"
[ "$VERDICT" = "CERTIFIED" ] && exit 0 || exit 1
