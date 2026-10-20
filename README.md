# treasury

A business-banking core in Haskell: businesses, accounts, a double-entry ledger,
and outbound ACH / wire payments that are submitted to a partner bank and
reconciled nightly.

```
                       ┌──────────────┐    ┌───────────────┐
  curl / frontend ───▶ │ treasury-api │───▶│   PostgreSQL  │◀──┐
                       │   (Yesod)    │    └───────────────┘   │
                       └──────────────┘                        │
                                              ┌────────────────┴───┐
                       ┌──────────────┐       │  treasury-workers  │
  partner bank  ◀────▶ │ mock-partner │ ◀────▶│ submit/poll/recon  │
                       └──────────────┘       └────────────────────┘
```

## Running it

```bash
nix develop
pg-start
cabal run treasury-api        # http://localhost:8080
cabal run mock-partner        # http://localhost:9400
cabal run treasury-workers -- submit
cabal run treasury-workers -- poll
```

See `scripts/demo.sh` for an end-to-end walk-through with curl, and `AGENTS.md`
for build, test and contribution rules.
