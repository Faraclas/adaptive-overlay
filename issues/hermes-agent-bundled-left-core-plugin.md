# hermes-agent: a bundled left-core plugin counts as missing

- Package: `app-ai/hermes-agent`
- Patch: `files/hermes-agent-0.22.7-bundled-left-core-plugin.patch` (used
  by 0.22.7)
- Upstream: none filed
- Status: unfiled (checked 2026-11-05)
- Drop when: upstream lets a packaged install ship a left-core plugin
  (`hermes_cli/left_core_migration.py` `plugin_present()` sees it), or we
  stop shipping the github-copilot plugin in core's bundled dir.

## Problem

From v0.22.6, GitHub Copilot is no longer in core (hermes-agent#144788);
it is the `github-copilot` plugin from NousResearch/hermes-labs-plugins.
Upstream installs it per profile at runtime (`hermes plugins install` into
`<HERMES_HOME>/plugins/github-copilot`, by `hermes update` or at agent and
gateway start). We cannot let Hermes fetch code at runtime, so USE=copilot
installs the plugin with Portage into
`site-packages/plugins/model-providers/github-copilot`, where core's
provider discovery (`providers/__init__.py` `_discover_providers`) loads it
for every profile.

`left_core_migration.plugin_present()` only looks in
`<HERMES_HOME>/plugins/<name>`. With the bundled copy loaded and working,
every agent and gateway start still finds Copilot "missing":

- with `security.allow_lazy_installs: false` (our hosts): it logs and
  queues "GitHub Copilot moved out of core and its 'github-copilot'
  plugin is not installed, so it is off ... run `hermes plugins install
  github-copilot`" on every start (wrong: it is on);
- with lazy installs on: it would fetch a second copy into the profile,
  which then shadows the Portage copy (home plugins win).

## Our patch

`plugin_present()` also returns True when
`providers._BUNDLED_PLUGINS_DIR/<name>/__init__.py` exists (the same dir
and test discovery uses; a leftover dir without `__init__.py` does not
count). Everything that keys off `plugin_present` then treats the profile
as migrated: no notice, no install, and `_left_core_installed:
[github-copilot]` is recorded in config.yaml once.

The plugin is installed only in the image, not in `${S}`: core's own
left-core tests (`tests/hermes_cli/test_left_core_provider_*.py`) assume
no bundled Copilot and fail with it in the source tree (12 failures seen in
the lab when it was there).

Tests: `tests/hermes_cli/test_left_core_bundled_plugin.py` (present with
the bundled copy, not with an empty dir; a start with lazy installs off is
quiet and installs nothing; without the copy it still reports Copilot off).
Lab, v0.22.7 with our patch stack (2026-11-05): 100 passed across the new
test, the plan-host tests and the existing left-core tests.

## Upstream

Upstream's Nix package does not ship left-core plugins either (no
`hermes-labs-plugins` in `nix/`), so this is not distro-specific: any
read-only packaged install that wants Copilot without a runtime fetch hits
it. `HERMES_BUNDLED_PLUGINS` ("Nix wrapper / packaged installs") only moves
the general plugin dir; `providers` discovery and `plugin_present` ignore
it. Worth an upstream issue once the setup has run on panther for a while.
