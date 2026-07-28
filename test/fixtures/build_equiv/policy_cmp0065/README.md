# build_equiv policy fixture: CMP0065 (toolchain-gated behavioral policy test)

Demonstrates the **`policy.json` fixture mode** — testing that yelu faithfully
carries a policy whose effect is *dynamic* (build-observable), gated on whether
the local toolchain actually exhibits it.

`CMP0065` controls whether cmake adds `-rdynamic` to executables (exporting
symbols to the exe's dynamic table). Where the toolchain honors it, `nm -D app`
differs between `OLD` (exports) and `NEW` (doesn't).

## How the mode works (`check_policy_fixture`)

`policy.json` declares `{ "policy", "states", "state_var" }`. The policy state is
a cmake **variable** — `cmake_policy(SET CMP0065 ${STATE})` in `CMakeLists.txt`,
`policy_set CMP0065 $STATE` in `main.yc` — varied per state via `-DSTATE=…`. yelu
carries the variable faithfully (a `policy_set` state is an expr, not a hardcoded
bool), so **one** yelu compile serves every state; the reference and yelu differ
only in the `-D` cell axis, like an option matrix cell. For each state the
harness builds both and fingerprints each build (artifacts + `nm` symbols). Then:

- **Gate (self-contained, no hard-coded toolchain knowledge):** if *vanilla
  cmake* produces an identical build across states, this toolchain doesn't
  exhibit the policy → **SKIP**.
- **Check:** if it differs, assert the **yelu** build matches the **reference**
  in each state — proving yelu carries the policy. A silent OLD→NEW coercion
  would show up as yelu's OLD build matching the reference's NEW while vanilla's
  states differ.

## Why it SKIPs on our cmake 4.3

cmake 4.x **removed CMP0065's `OLD` behavior** (`cmake_policy(SET CMP0065 OLD)`
is a hard error), so the `OLD` reference build fails → SKIP (no baseline). This
is the intended toolchain/version gating: the test runs where the policy is
settable both ways *and* the toolchain honors `-rdynamic`, and skips otherwise.
To exercise the PASS path locally, point it at a policy your cmake still lets you
set both ways whose effect your linker exhibits.
