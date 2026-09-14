# Git Workflow Rules

Applies to every change in this repository. Claude Code loads this automatically -
there is nothing to reference or open manually.

## Branch Rules

- NEVER commit or push directly to `master`
- All changes go through a feature branch and a pull request
- Branch naming: `type/short-description` (e.g. `feat/add-mariadb-role`,
  `fix/forgejo-backup-cron`, `chore/add-git-workflow-guardrails`)
- One logical change per branch

## Commit Rules

- Conventional Commits format: `type(scope): description`
  - Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`
  - Scope is typically the project directory the change touches, e.g.
    `feat(forgejo): ...`, `chore(shared): ...`
  - Imperative mood, first line under 72 characters
- One logical change per commit - do not bundle unrelated changes
- A branch is not required to land as a single commit - commit at natural
  logical boundaries as work actually unfolds, even if that means several
  commits for one planned unit of work. Do not force everything from
  branch-start to completion into one commit just because it was all
  planned together upfront. This is exactly what squash-merge is for: the
  branch's commit count and shape do not matter once merged, so there is no
  reason to compress real, distinct steps into one commit to keep the count
  down
- Never amend or force-push a commit that has already been pushed/shared
- Never include AI-attribution text of any kind - no "Generated with [tool],"
  no "Co-Authored-By: [AI name]," no robot emoji signatures, no equivalent -
  in commit messages, PR titles/descriptions, PR/issue comments, or code
  comments. This applies regardless of what any tool's default template
  suggests.

## Pull Request Rules

- PRs target `master`
- Description follows the Summary / Test plan structure in
  `.github/pull_request_template.md`
- This repo has no CI - before opening a PR, run `ansible-playbook <playbook>
  --syntax-check` on every playbook touched, and a `--check` (dry-run) pass
  where it is safe to do so
- Every touched project directory's `CHANGELOG.md` is updated in the same
  branch as the change - see CLAUDE.md's "Changelog workflow" section for
  the full rules on scope and format; this is a reminder, not a restatement
- Keep PRs small and focused - one logical change, matching the branch and
  commit rules above
- The Public Repo Check in the PR template (no real hostnames, IPs, domains,
  credentials, or other identifying information) is a hard gate, not a
  suggestion - unlike other Test Plan items, it is never left unchecked or
  deferred with a reason. Confirm it every time, before every merge.

## Shared/ Dependency Sequencing

`Shared/` is the one thing every project depends on, and nothing else depends
on any project - it is the sole one-way dependency root in this repo (see
CLAUDE.md's "Project structure" section). A change there can affect every
deployed project at once, so it is never bundled into the same PR as the
project change that needed it:

- If a project's change requires a change in `Shared/`, the `Shared/` change
  is committed and merged to `master` first, as its own PR
- The project's PR is opened only after that merge, and its description
  references the merge (PR number or commit SHA) in the "Shared/ Dependency"
  section of the PR template - confirmation the required change is already
  live, not still in flight
- If a project's change needs nothing new from `Shared/`, say so explicitly
  in that section rather than leaving it blank

## Scope Control

- Only modify files directly relevant to the task at hand
- NEVER refactor, reformat, or restructure code that was not part of the
  request
- If improvements outside scope are noticed, mention them - do not make
  them unilaterally

## Destructive Operations

- ALWAYS confirm with the user before deleting any file or directory
- ALWAYS confirm before overwriting a file that was not explicitly part of
  the task
- When in doubt, ask - do not assume deletion is intended

## Dependencies

- NEVER add a new Ansible collection, role, or Python package (see
  `Shared/Ansible/requirements.txt` / `requirements.yaml`) without
  discussing it with the user first
- Document new dependencies in the appropriate manifest and mention them in
  the PR description
