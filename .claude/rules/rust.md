---
paths:
  - "crates/**/*.rs"
---

# Rust

The Rust layer does not reimplement the maths. Every operation delegates to the
Solidity through an in-memory EVM (revm), and `alloy::sol!` generates the
bindings from the Foundry JSON artifacts in `out/`.

So `cargo test` depends on `out/` already existing. Run `forge build` first — a
missing or stale `out/` surfaces as a confusing macro/binding compile error
rather than a clear "artifacts are missing".
