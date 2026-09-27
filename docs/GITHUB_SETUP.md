# GitHub repository settings for S1-01

These are actual GitHub settings, not files that Git automatically applies.
The repository owner must save them on GitHub. Writing this guide alone does
not protect `main`.

## Verified repository status (2026-09-27)

A classic rule for `main` has been saved. GitHub reports the branch as protected
and requires **Mobile checks** and **Backend checks** for everyone. PR #1 was
approved by Olena and merged. Do not create a duplicate protection rule.

The detailed protection endpoint and collaborator list require authenticated
access that was not available to this audit. Reopen the existing rule to
confirm **Require approvals: 1** and the other settings in the table below;
confirm each teammate has accepted repository access. The table describes the
intended configuration, not a claim that every setting was independently read.

See [S1-01.md](S1-01.md) for build, emulator, review, and merge evidence.

## 1. Confirm team access

Open [Settings → Collaborators](https://github.com/emrecandir9/JamScan/settings/access).
If they are not already collaborators, invite Gloria, Olena, and Oliver by
their confirmed GitHub usernames. Ask them to accept the invitations and
verify that they can push a task branch. Do not guess usernames or send
passwords/tokens to each other.

## 2. Let CI register the checks

Push the S1-01 task branch and open its PR. In the
[Actions tab](https://github.com/emrecandir9/JamScan/actions), wait for the
`CI` workflow to finish successfully. GitHub needs a recent run to offer the
check names in the protection settings.

## 3. Protect main

Open [Settings → Branches](https://github.com/emrecandir9/JamScan/settings/branches).
Under **Branch protection rules**, select **Add classic branch protection
rule** (or **Add rule**). If a matching rule already exists, edit that rule.

Set **Branch name pattern** to exactly `main`, then configure:

| Setting | Value |
| --- | --- |
| Require a pull request before merging | Enabled |
| Require approvals | Enabled; **1** approval |
| Dismiss stale pull request approvals when new commits are pushed | Enabled |
| Require status checks to pass before merging | Enabled |
| Required checks | **Mobile checks** and **Backend checks** |
| Require branches to be up to date before merging | Enabled |
| Require conversation resolution before merging | Enabled |
| Do not allow bypassing the above settings | Enabled, including owner/admin |
| Allow force pushes | Disabled |
| Allow deletions | Disabled |

Save the rule. Do not enable **Lock branch**, which would prevent normal PR
merges. One approval is sufficient for this four-person team; the author
cannot provide that approval themselves.

These options follow GitHub's
[protected-branch documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches).
Protection is supported for public repositories on GitHub Free.

## 4. Verify the result

1. Reopen the saved rule and confirm the exact branch pattern and settings.
2. Open the S1-01 PR; without a teammate approval, GitHub should block merging
   and show that review is required.
3. Confirm both named checks appear and must pass.
4. Keep a screenshot of the saved rule and successful checks as course evidence.
5. Have another team member approve and merge after all conditions are met.

Do not test protection by pushing unwanted commits to `main`.

## Optional cleanup preference

Under **Settings → General → Pull Requests**, enable **Automatically delete
head branches** to remove remote task branches after merging. The team uses
**Squash and merge** for a readable history; no extra `develop` branch is needed.
