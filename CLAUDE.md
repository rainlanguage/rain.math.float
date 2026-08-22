# CLAUDE.md

## Deploying is irreversible

Contracts land at the same address on every supported network via the Zoltu
deterministic proxy: the address is a function of init code + salt, not of the
branch or the deployer. Deploying identical bytecode from any branch therefore
lands exactly where a `main` deploy would.

```bash
gh workflow run manual-sol-artifacts.yaml --ref <branch> -f suite=decimal-float
```

There are two suites. Use `log-tables` only when the table bytecode changes,
which is rare — and when the tables ARE being redeployed, deploy `log-tables`
before `decimal-float`.

Deploys never gate merges: publishing a release and broadcasting a deployment
are decoupled, and no PR should carry a "redeploy before merge" instruction.

## Pinned deploy constants: two tiers, not one

`src/lib/deploy/LibDecimalFloatDeploy.sol` holds two kinds of constant that
look alike and must not be treated alike. Both are DERIVED from bytecode, so
pinning never waits on a broadcast.

- **Unsuffixed** — the current head's address and codehash. Any source change
  to `LibDecimalFloat` or `LibFormatDecimalFloat` invalidates them; regenerate
  and commit them in the same PR that changes the source.
- **`*_<major>_<minor>_<patch>`** — a frozen record of what one published
  soldeer tag's own bytecode deploys to. Written once when that tag is
  published, and **never updated afterwards**.

Do not "correct" a suffixed pin that disagrees with current source. It is
supposed to disagree once the source moves on; rewriting a release's record to
match new code destroys the only thing that record holds.

## Arithmetic errors on nonsense, and never on truncation

There is no NaN, no Infinity and no negative zero. Operations revert rather
than produce a special value.

Exponent overflow and underflow both revert from the public arithmetic surface.
Coefficient truncation of values too large for `int224` is **deliberately
tolerated in silence**, because it preserves the order of magnitude, which is
the property callers depend on. That asymmetry is a decision, not an oversight
to fix.
