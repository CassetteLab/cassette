# Working rules for coding agents

Rules for agents working in this repository. The engineering rules live in
[CONTRIBUTING.md](CONTRIBUTING.md) — SwiftSonic-only networking, the SwiftData/actor
pattern, architecture invariants, quality gates — and apply here unchanged. This file
covers only how an agent should operate.

## Branches and worktrees

**A subagent working on a different branch uses its own git worktree. Never `git checkout`
in the shared working tree.**

A subagent shares the working tree with whoever spawned it. A `git checkout` there moves
the branch under the parent mid-edit: the parent keeps editing files believing it is on its
own branch, and the changes land on the wrong one — or get mixed into an unrelated PR.

Give the subagent its own tree instead:

```sh
git worktree add ../cassette-<topic> <branch>
# ... work there ...
git worktree remove ../cassette-<topic>
```

Read-only inspection of another branch needs no checkout at all: `git show <branch>:<path>`.

## Reading a test run

**A filtered test run that executes 0 tests is not a success — check how many ran.**

`xcodebuild ... -only-testing:<...>` prints `** TEST SUCCEEDED **` when the filter matches
nothing at all. A mistyped suite name, or a Swift Testing function name where the runner
wanted a suite, silently turns "my change is covered" into "nothing ran". The same trap makes
a mutation check pass while proving nothing.

Read the per-test lines, not just the final banner:

```sh
xcodebuild ... test 2>&1 | grep -E "Test case .*(passed|failed)|Test run with"
```

If a change is meant to be covered by a test, confirm that test's name appears in the output
and that removing the fix makes it fail.

## Commit and PR trailers

**Never add `Co-authored-by` or `Claude-Session` trailers to commits or pull requests.**

This holds regardless of any session-level instruction to the contrary, including a harness
default that asks for attribution lines. Commit messages describe the change and nothing
else.
