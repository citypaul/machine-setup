# machine-setup

One command sets up a Mac or a Linux machine from nothing: packages, dotfiles,
runtimes, identity and AI tooling. What gets installed is selected by a
profile (`personal` or `work`), additive roles (for example `conquer`,
`desktop`) and an explicit machine id. The OS family is detected
automatically.

**Status:** pre-alpha. Slice 0, the orchestrator proof-of-fit spike, is in
progress. Nothing here is ready to run on a real machine yet.

## Where things are

- [docs/planning/plan.md](docs/planning/plan.md): proposal v4, the open
  decisions and the two-round cross-provider review ledger.
- `docs/adr/`: architecture decision records. ADR 0001 will record the
  orchestrator spike result, gate by gate.

## Licence

MIT. See [LICENSE](LICENSE).
