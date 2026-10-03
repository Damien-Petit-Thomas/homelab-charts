# Contributing

## Toolchain

Every tool is pinned in `mise.toml` and locked in `mise.lock`; CI installs
the same versions with `jdx/mise-action`.

```bash
mise trust && mise install   # installs the pinned versions, checksums verified
pre-commit install           # git hooks, run from a mise-activated shell
mise run lint                # every hook on the whole tree, as in CI
```

## Commits

[Conventional Commits](https://www.conventionalcommits.org/), with the chart
as scope: `feat(vaultwarden): add backup CronJob`. release-please derives
versions and changelogs from them ([ADR 0003](docs/adr/0003-release-please.md)):

| Commit | Release |
|---|---|
| `fix(<chart>): ...` | patch |
| `feat(<chart>): ...` | minor |
| `feat(<chart>)!: ...` or a `BREAKING CHANGE:` footer | major |
| `chore`, `ci`, `docs`, `test`, `refactor` | none |

## Pull requests

`main` accepts pull requests only. A pull request merges when `ci-ok` and
`zizmor` pass. A new CI job must be added to the `needs` of `ci-ok`, never to
the ruleset ([ADR 0004](docs/adr/0004-solo-maintainer-branch-protection.md)).

## Tests

Every template change comes with unit tests. Every validation (schema, `fail`
guards, policies) comes with a negative test that checks the error message,
not only the failure: a check that fails for the wrong reason proves nothing.

## Repository settings

The branch ruleset is versioned in `.github/rulesets/`. After changing it in
GitHub, export it with `scripts/export-ruleset.sh` and commit the result.
