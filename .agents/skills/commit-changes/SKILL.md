---
name: commit-changes
description: Create a signed-off Git commit from current repository changes with a technically precise Conventional Commit message. Use when asked to commit changes or explicitly invoking commit-changes; honor message-only requests without committing.
---

# Commit Current Changes

Review the current changes, stage the intended work, and create a real commit
with a message useful for debugging, git bisect, code archaeology, and review.

## 1. Scope and Authorization

- An explicit invocation of this skill, or a request to commit changes, authorizes
  staging and committing within the requested scope. Carry the workflow through
  the commit; do not stop after drafting a message or ask for the same approval
  again.
- Requests to explain, edit, or review this skill do not invoke its commit
  workflow. Requests for a message only, a preview, or no commit remain read-only:
  do not stage files or commit.
- Respect any files, changes, or commit boundaries specified by the user. Without
  a narrower scope, inspect current staged and unstaged changes and relevant
  untracked files; do not assume every untracked file belongs in the commit.
- This workflow does not authorize source edits, unrelated fixes, pushing,
  amending commits, resetting work, or rewriting history.

## 2. Inspect the Actual Changes

- Start with `git status --short --untracked-files=all`, `git diff`, and the full
  `git diff --cached`. Inspect relevant new files and non-text assets directly;
  untracked content is absent from both diffs.
- Inspect surrounding code when needed to understand behavior and motivation.
  Never derive a message solely from conversation history or a diff summary.
- Distinguish intended changes from unrelated work, including existing staging.
  If ownership or scope is unclear, ask a focused question before changing the
  index or committing the ambiguous content.
- If there are unrelated logical changes, identify the concerns and recommend
  separate commits. Obtain agreement on the grouping before splitting or staging
  them; do not silently bundle unrelated work or disturb existing staging.
- If there are no intended changes to commit, report that and stop without an
  empty commit.

## 3. Stage and Review

- Stage the intended paths or hunks explicitly. Preserve unrelated staged and
  unstaged work; do not use a blanket `git add .` or `git add -A` without inspecting
  and establishing the scope of everything it would include.
- Read the complete final `git diff --cached` and run `git diff --cached --check`.
  The staged patch is the source of truth for the message and the commit. Recheck
  it if the index changes after review.
- Use relevant validation already performed when it still covers the staged
  changes. Add or repeat checks only for new changes, failures, or concrete risks;
  do not introduce tests or tooling just to make a commit.

## 4. Write the Message

Use Conventional Commits: `type(scope): concise description`.

- Keep the subject under 72 characters and use imperative mood.
- Name the affected component or capability using terminology from the codebase.
  Describe the actual change; avoid vague phrases such as "update", "improve",
  "enhance", "fix stuff", or "various changes".
- Choose the type that matches the staged implementation, such as `feat`, `fix`,
  `docs`, `refactor`, `test`, `perf`, `build`, `ci`, or `chore`.
- For non-trivial changes, include a body explaining what changed, the underlying
  problem or motivation, and how important behavior or architecture works.
  Preserve relevant API, compatibility, error-handling, performance, resource
  lifecycle, concurrency, and synchronization details.
- Write for someone who has not read the conversation. Describe the implemented
  result, not an intended result. Do not mechanically list every modified file,
  repeat the subject, add redundant bullets, or use marketing language.
- Make only supported claims, including claims about validation. When useful,
  distinguish checks run from checks not performed.
- Mark actual breaking changes with `!` or a `BREAKING CHANGE:` footer and explain
  their impact and migration path.

## 5. Create and Verify the Commit

- Briefly state the selected scope and commit subject, then execute
  `git commit --signoff` (`-s`) under the authorization above. Prefer a temporary
  message file and `git commit --signoff --file <path>` for a multiline message;
  do not interpolate generated message text into executable shell code.
- Use the committer identity resolved by `git var GIT_COMMITTER_IDENT` and let Git
  append the `Signed-off-by` trailer. If the identity cannot be resolved, ask for
  the missing information; do not invent an identity or silently change Git
  configuration.
- Respect repository hooks. If the commit fails, report the reason and preserve
  the work; do not bypass hooks, broaden scope, or claim success. If an authorized
  retry changes staged content, review that content again first.
- After success, inspect `git log -1 --format=fuller`,
  `git show --stat --oneline HEAD`, and `git status --short --untracked-files=all`
  to verify the created commit and identify remaining work. Confirm that the
  commit message contains a `Signed-off-by` trailer matching the committer identity.
  Do not push.

## 6. Delivery

For a completed commit, report:

- Commit ID and complete commit message.
- A brief explanation of how the message represents the committed changes.
- Validation results, checks not performed, and any remaining staged, unstaged,
  or untracked work.

For an explicitly message-only request, return the proposed subject, complete
message, and brief rationale without staging or committing. If nothing is staged,
report that instead of inventing a message from unstaged changes.
