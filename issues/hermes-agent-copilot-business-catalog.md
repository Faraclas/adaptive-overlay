# hermes-agent: Copilot plan host in base_url hides the live model catalog

- Package: `app-ai/hermes-agent`
- Patch: `files/hermes-agent-0.22.5-copilot-plan-host-catalog.patch` (used
  by 0.22.5)
- Upstream: issue https://github.com/NousResearch/hermes-agent/issues/142480,
  PR https://github.com/NousResearch/hermes-agent/pull/142481
- Status: open (checked 2026-10-28)
- Drop when: a packaged release contains #142481 (or another fix for
  #142480) and the picker lists the live catalog with
  `base_url: https://api.business.githubcopilot.com`.

## Problem

Seen on panther after the first 0.22.5 install (2026-10-28): the model
picker shows the old curated Copilot list. Tomcat (0.21.5) shows the live
list (15 models) with the same dotfiles config:

```yaml
model:
  provider: copilot
  base_url: https://api.business.githubcopilot.com
```

`hermes_cli/models.py` `_configured_relay_base_url()` (added for #121387,
after 0.21.5) treats any `model.base_url` that differs from the profile or
registry endpoint (`https://api.githubcopilot.com`) as a custom relay.
`provider_model_ids()` then calls `_relay_model_catalog()`, which only
supports API-key profiles (Copilot's `auth_type` is `copilot`), and falls
back to the static list. `_copilot_catalog` never runs. No request is
made, so nothing is logged.

The business host is the account's real endpoint (the token exchange
reports it as `endpoints.api`); keep it in the config.

Not caused by our other patches: `hermes-agent-copilot-pat-discovery.patch`
only changes the catalog request headers.

## Upstream

- #142480 (open, P2, `provider/copilot`) reports it for a Business account.
- #142481 (BlueberryDuck, open, no reviews; GitHub shows merge conflicts
  as of 2026-10-28). teknium1 asked for a generic rule after Copilot left
  core (#144788): a bare `https://<host>` root of a host the provider's
  profile claims (`providers.profile_for_host`, profile `hostnames`) is
  the provider's own endpoint. The plugin claims `githubcopilot.com`, so
  the plan hosts are covered. Path, query, user info, non-default port
  and plain http stay relays.
- The PR author tested a real Business account only with an earlier,
  Copilot-specific revision; the current revision with a stubbed catalog.

## Our patch

Same helper name (`hermes_cli/route_identity.is_claimed_root_route`), same
rule and the same one-line hook in `_configured_relay_base_url()` as the
PR. 0.22.5 has no `profile_for_host` or profile `hostnames`, so the claim
is a table in `route_identity.py`: `copilot` -> `githubcopilot.com`. It
does not claim `models.github.ai` (the upstream plugin does; we don't need
it). Tests: `tests/hermes_cli/test_models_claimed_host_route.py`, the PR's
cases run against the real Copilot profile.

Safe for credentials: the native Copilot catalog always fetches from
`api.githubcopilot.com/models`, whatever `base_url` says.

Verified in containers (2026-10-28): the new tests plus
`tests/hermes_cli/test_models_relay_base_url.py` pass (33 passed) on the
fully patched 0.22.5 tree; `verify-hermes-agent.sh` checks the helper and
that `_configured_relay_base_url("copilot")` is empty for the business
root. Not yet tested live on panther.

## Notes

- After the live check on panther, offer a PR comment (user approves the
  text first): the same rule, backported to 0.22.5, lists the live catalog
  for a real Business account.
- When moving to a release with #144788 (Copilot as a plugin), check
  whether #142481 landed; if not, the patch must be redone against that
  core, using `profile_for_host`.
