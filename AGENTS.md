# AGENTS.md

Guidance for coding agents (and humans) working in this repository.

## What this is

`treasury` is a small business-banking core: businesses own accounts, accounts
hold balances in a double-entry ledger, and outbound payments (ACH / wire) move
through a lifecycle driven by background workers that talk to a partner bank.

| Package | Purpose |
|---|---|
| `treasury-core` | Persistent schema (`Treasury.Model`), ledger, payments, errors |
| `treasury-partner-client` | HTTP client for the partner bank + `mock-partner` server |
| `treasury-api` | Yesod JSON API (`treasury-api` executable) |
| `treasury-workers` | `treasury-workers submit|poll|reconcile` background jobs |

## Toolchain

Everything runs inside the Nix dev shell. Prefix commands with `nix develop -c`
or enter the shell once with `nix develop`.

```bash
nix develop                       # GHC 9.10, cabal, ormolu, hlint, ghciwatch, postgres 16
pg-start                          # local postgres on :5433 (databases: treasury, treasury_test, treasury_core_test)
cabal build all                   # builds every package and test suite (-Wall -Werror)
cabal test all                    # unit tests + ledger properties + API tests (needs pg-start)
cabal run treasury-api            # :8080
cabal run mock-partner            # :9400, stand-in for the partner bank
cabal run treasury-workers -- submit     # or: poll | reconcile, add --once for a single tick
ormolu --mode inplace $(git ls-files '*.hs')
hlint .
```

`ghciwatch --command 'cabal repl treasury-core' --test-ghci 'pure ()'` gives a
fast reload loop for a single package.

## Rules

1. **The project builds with `-Werror`.** Unused imports, incomplete patterns and
   name shadowing are compile errors. Run `cabal build all` before you call
   anything done; `cabal repl` loading is not sufficient.
2. **Schema changes go in `Treasury.Model`** (Persistent quasi-quote). Migrations
   are applied automatically at startup via `runMigrations`; do not hand-write SQL.
3. **Money is integer cents.** Never use `Double` for amounts.
4. **Every movement of money is a balanced journal** posted through
   `Treasury.Ledger.postJournal`. Never insert `LedgerEntry` rows directly.
5. **Format with ormolu, lint with hlint** before committing. The pre-commit hook
   in `scripts/pre-commit` runs both; install it with `scripts/install-hooks`.
6. Tests live next to the package they test (`<pkg>/test`), use hspec, and are
   discovered automatically — add a `*Spec.hs` module and list it in the cabal file.
7. Commit messages: `<package>: <summary>` (e.g. `treasury-core: add Returned status`).
