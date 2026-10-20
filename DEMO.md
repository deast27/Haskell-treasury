# Demo runbook — Devin on a Mercury-shaped Haskell codebase

Audience: Mercury engineering. Theme: the things Ian Duncan's
["A Couple Million Lines of Haskell"](https://blog.haskell.org/a-couple-million-lines-of-haskell/)
says keep a large Haskell system alive — compiler-driven refactors, domain
errors instead of transport errors, incantations encoded in types,
instrumentable boundaries, tests at your own layer, durable execution — are
exactly the work Devin is good at absorbing.

## The codebase

`treasury` is a deliberately small business-banking core on Mercury's stack
(GHC 9.10, Yesod, Persistent/Esqueleto, PostgreSQL, Nix, `-Werror`, ormolu,
hlint, hspec/QuickCheck). It ships with the institutional debt the article
describes, each filed as a GitHub issue:

| # | Issue | Article theme | Seeded in |
|---|---|---|---|
| 1 | `Returned` status + currency-aware `Money` | mechanical, compiler-guided refactor | `Treasury.Money`, `Treasury.Payments.Status`, `Workers.Poll` |
| 2 | `PaymentError` instead of HTTP status exceptions | design for your domain, not your transport | `Treasury.Errors`, all three workers, `Ledger.postJournal` (throws 500) |
| 3 | `Transact`/`commit`: notification always in the transaction | make the right thing easy | `cancelPayment`, `Workers.Submit/Poll/Reconcile` (two `runDb` calls) |
| 4 | Record-of-functions partner client + Monoid interceptors + otel spans | designing for introspection | `Treasury.Partner.Client` (+ `TREASURY_PARTNER_STUB` hack) |
| 5 | Ledger property tests | tests at your own layer | `Ledger.splitFee` loses a cent (`percentOf` floors both shares) |
| 6 | One workflow instead of three cron state machines | durable execution / Temporal | `treasury-workers` |
| 7 | Toolchain bump (nixpkgs, GHC 9.12) | day-one cost, Nix | `flake.nix` |

Plus a no-PR opener: ask Devin how a wire gets settled and what happens if the
partner acks but never settles (see `issues/00-question.md` in the plan).

## Suggested 40-minute flow

| Time | What | Talk track |
|---|---|---|
| 0–5 | Show the repo, `nix develop`, `cabal build all`, run `scripts/demo.sh` against the live stack | "This is a miniature of your world: Yesod, persistent, `-Werror`, nix." |
| 5–8 | Kick off issues **1, 2, 3** as three parallel Devin sessions (from GitHub issues or the Devin UI) | "Half your engineers have <1 year of Haskell. Devin reads the whole codebase before it starts." |
| 8–15 | Ask the codebase question (issue 0) in a fourth session / DeepWiki while the others build | Institutional dark matter: the 24 h sweep only catches `Submitted`, not `PartnerAcked`; notifications outside the txn. |
| 15–25 | Open the first PRs as they land; walk through the diff, CI (ormolu, hlint, build, tests) | Mechanical refactor: "change a type, the compiler hands you the list" — Devin works through the list. |
| 25–35 | Run issue **5** live; watch Devin write the `splitFee` property, see it fail, find the floor-twice bug, fix it | "Types can't tell you cents vs dollars. Tests at your layer can." |
| 35–40 | Audience picks issue **4** or **6**; discuss Temporal/`hs-temporal-sdk` as the stretch | Observability and durable execution are Mercury's own words. |

## Reset between demos

```bash
gh issue list --label demo --state closed --json number -q '.[].number' | xargs -n1 gh issue reopen
git branch -r | grep devin/ | sed 's|origin/||' | xargs -n1 git push origin --delete   # optional
```

The seeded debt lives on `main`; Devin's PRs are never merged, so reopening the
issues is the whole reset.

## Running locally

```bash
nix develop
pg-start
cabal run mock-partner &            # :9400
cabal run treasury-api &            # :8080
cabal run treasury-workers -- submit &
cabal run treasury-workers -- poll &
scripts/demo.sh
```

Mock partner rules: amounts ending in `13` cents are returned after ack,
`99` cents are rejected, counterparty names containing "slow" take 15 s.
