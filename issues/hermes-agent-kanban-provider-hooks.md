# hermes-agent: kanban needs provider-resolution hooks

- Package: `app-ai/hermes-agent`
- Patch: none
- Upstream: issues #116452, #134517, #122703; PR #86633
- Status: watching (checked 2026-10-25)
- Drop when: n/a (no patch). Close when a release lets the kanban
  dispatcher check or rewrite a task's provider/model before claiming it.

## Problem

The kanban dispatcher claims a task without checking that its provider
and model can run, and offers no hook to reject or rewrite them. Tasks
then fail after claim (e.g. dead credentials, unsupported model).

## Upstream

- https://github.com/NousResearch/hermes-agent/issues/116452: pre-dispatch
  and pre-create hooks. Open. PRs #116608 and #116663 closed unmerged.
- https://github.com/NousResearch/hermes-agent/issues/134517: claim-time
  model/provider allow/rewrite/reject. Open, `needs-decision`.
- https://github.com/NousResearch/hermes-agent/issues/122703: no provider
  probe before claim. Open. #126153 (merged 2026-09-28, salvaging
  #122716) makes dead credentials exit 78; the pre-claim probe PR #122893
  closed unmerged.
- https://github.com/NousResearch/hermes-agent/pull/86633: generic
  pre-claim gate. Open.
- Kanban card: `hermes_upstream` / t_d7df448e.
