# mathlibslop — a verification-gated archive for AI-generated Lean proofs

A **"formal arXiv" for the AI era**: a place to park machine-generated Lean 4
proofs where each entry is **machine-certified**, reproducible, and frozen —
*correctness guaranteed by the Lean kernel, elegance not required.*

This is **not** a reusable library (that's [mathlib](https://github.com/leanprover-community/mathlib4)).
It is the missing cousin of Isabelle's [Archive of Formal Proofs](https://www.isa-afp.org/),
built for **Lean + AI-generated proofs + a soundness gate**.

## The gate (`verify.sh`)

A proof is **CERTIFIED** iff:

1. it builds / elaborates with **no errors**, and
2. **every** claimed top-level result's `#print axioms` set is a subset of the
   allow-list — by default the three standard axioms:
   `propext`, `Classical.choice`, `Quot.sound`.

The axiom check is the *entire* gate, because every known cheat shows up there:

| cheat | appears in `#print axioms` as |
|---|---|
| `sorry` / `admit` | `sorryAx` |
| `native_decide` | `Lean.ofReduceBool` |
| any custom `axiom` | its own name |

So nothing unsound can pass without being named — that's the property that makes
it safe to accept proofs no human can read.

## An entry

```
entries/NNNN-name/
  entry.toml      # metadata: authors, toolchain, mathlib rev, claimed results, provenance
```

The **project source** is referenced by pinned toolchain + mathlib revision so
the build is reproducible (freeze the toolchain per entry to beat bit-rot — a
living library can't, an archive can).

## Usage

```bash
# certify a Lake project
./verify.sh --name alpoge-riemann \
    --project /path/to/lean/project \
    --result Main:riemannHypothesis

# certify a single standalone file (self-test / small proofs)
./verify.sh --name selftest --file /tmp/t.lean --result _:good
```

Certificates (tamper-evident, sha256-stamped) land in `certs/`.

## Status

- **Entry 0001** — Alpöge's Claude/Fable-assisted Riemann Hypothesis proof
  (175,187 files / 17.4M lines). Verification pending clean build on the tower.
