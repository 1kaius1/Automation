## Summary

<!-- What changed and why. -->

## Shared/ Dependency

<!-- If this change requires updates to Shared/, those changes must already be
merged to master - in their own PR, opened and merged first - before this PR
is opened. Never bundle a Shared/ change into the same PR as the project
change that depends on it. Reference the confirming merge here. -->

- Shared/ PR or commit: <!-- e.g. #12 / abc1234, or "N/A - no Shared/ changes required" -->

## Test Plan

<!-- Checklist of what was verified. Include `ansible-playbook --syntax-check`
results and, where safe, a `--check` dry run. If an item is intentionally left
unchecked (e.g. not yet re-run against a live cluster), say why rather than
leaving it unexplained. -->

- [ ] `ansible-playbook <playbook> --syntax-check`
- [ ]

## Changelog

- [ ] `CHANGELOG.md` updated for every project directory this PR touches

## Public Repo Check

**Required before merge - unlike the Test Plan items above, this is never left
unchecked or deferred.**

- [ ] No real hostnames, IPs, domains, credentials, or other identifying
      information - only `.example` files are committed; secrets go through
      Ansible Vault
