# Zig EVM Roadmap

Zig EVM is an **embeddable execution core, not a chain.** The goal is a
spec-conformant, high-performance EVM that any project can link against — an L2
sequencer, a rollup prover, an agent runtime, a simulator, an indexer, or a
research testbed — and get parallel transaction execution without adopting a
new network, consensus layer, or token.

This document describes where the project is headed and what "production" means
for a library like this.

## Vision

The EVM is becoming a hot path again. In 2026 the pressure on execution is
coming from new places: agentic payments and high-frequency, machine-initiated
transactions; on-chain and verifiable AI workloads that settle results to the
EVM; real-world-asset (RWA) settlement that needs deterministic, auditable
execution; and the broader parallel-EVM wave (Monad, MegaETH, Sei, Reth's
execution extensions) that treats single-threaded execution as the bottleneck
to remove.

Zig EVM's bet is narrow and specific: **the execution engine should be a small,
embeddable, parallel-capable library** — not something you can only get by
running a whole client. Wave-based parallel execution gives a measured
**5-6x throughput gain over sequential execution** on independent-transaction
workloads (see the README benchmark and `docs/BENCHMARK.md`); the stable C ABI
lets Python, Rust, JavaScript, and C embed it directly.

## Milestones

### Now (shipped)
- Core EVM with the opcode set documented in the README and `docs/OPCODES.md`.
- 256-bit arithmetic, gas metering, nested call frames (CALL/DELEGATECALL/STATICCALL).
- Wave-based parallel batch executor with O(n) hash-based dependency analysis,
  work-stealing thread pool, and optional speculative execution with rollback.
- Stable C ABI and FFI bindings for Python, Rust, JavaScript, and C.

### Next (near-term)
- Broaden Ethereum execution-spec / consensus-test conformance coverage and
  publish a pass/fail matrix per fork.
- Differential fuzzing harness against a reference EVM (e.g. `revm`/`geth`) to
  catch divergence on adversarial bytecode.
- Reproducible, machine-published benchmarks (fixed hardware profile, scripted
  workloads, conflict-rate sweeps) so the 5-6x figure is independently checkable.
- Versioned FFI surface with a documented ABI stability policy.

### Later (direction)
- Reference integration: embed Zig EVM as the execution layer behind a minimal
  sequencer on a cheap devnet/L2 to demonstrate end-to-end embedding.
- Deeper parallel scheduling (finer-grained conflict detection, adaptive
  wave sizing based on observed conflict rate).
- Tracing/inspection hooks suited to agent runtimes and verifiable-AI pipelines
  that need per-step execution transcripts.

## Cheapest path to production

For an embeddable engine, "production" does **not** mean launching a chain.
Launching a chain is the most expensive, highest-risk way to prove an execution
engine — it drags in consensus, networking, token economics, and operations
that have nothing to do with whether the EVM executes bytecode correctly and
fast.

**The cheapest path to production is to ship Zig EVM as a spec-conformant,
versioned library plus one reference integration on a cheap devnet or L2** —
and to treat "production-viable" as a checklist about the *library*, not about
running a network:

1. **Execution-spec / consensus-test conformance.** Pass the Ethereum
   execution-spec and consensus test suites for the supported fork(s), and
   publish the pass/fail matrix. Conformance is the contract embedders rely on.
2. **Differential fuzzing vs. a reference EVM.** Continuously fuzz Zig EVM
   against an established EVM (e.g. `revm` or `geth`) and treat any state/gas
   divergence as a release blocker.
3. **Security audit.** Independent audit of the interpreter, gas metering, the
   parallel scheduler (conflict detection / rollback correctness), and the FFI
   boundary (memory safety across the ABI).
4. **Stable, versioned FFI.** A semver'd C ABI with a written stability policy,
   so embedders can upgrade without silent breakage.
5. **Reproducible benchmarks.** Scripted, fixed-hardware benchmarks — including
   conflict-rate sweeps — so throughput claims (the 5-6x parallel gain) are
   reproducible by third parties, not just asserted.
6. **One reference integration.** Embed the library behind a minimal execution
   layer on a cheap devnet/L2 (not a mainnet launch) to prove the embedding
   story end-to-end.

Meeting that checklist makes Zig EVM safe for others to embed — which is the
only definition of "production" that matters for a library. It also costs a
fraction of what launching and operating a chain would, and it keeps the
project honest: the value is the engine, so the engine is what gets proven.

## A note on honesty

The parallel speedup is real but **workload-dependent.** The 5-6x figure holds
for batches of largely independent transactions; workloads dominated by
shared-state contention (e.g. many trades against one AMM pair, or long
single-sender nonce chains) will see far less. Every performance claim in this
project is either the measured 5-6x parallel gain / the opcode count as stated
in the README, or is explicitly labeled illustrative. See the "Limitations"
sections of the README and `docs/PARALLEL.md`.
