# Working together on GitHub

## Five terms you need

| Term | Meaning |
| --- | --- |
| Repository | The shared project and its change history. |
| Clone | Your local copy of that repository. |
| Branch | A separate line of work for a task. |
| Commit | A named checkpoint of selected changes on your branch. |
| Pull request (PR) | A request to review and merge your branch into `main`. |

**Commit saves locally. Push uploads to GitHub. Pull downloads changes.**
All four teammates clone the same repository; you do not need separate forks.

## One-time setup for each teammate

1. Sign in to your GitHub account and accept the repository invitation.
2. Install Git and the tools described in [SETUP.md](SETUP.md).
3. Configure the name and email shown on your commits. Use your own values;
   GitHub offers a private `noreply` email in your account email settings.

```bash
git config --global user.name "Your Name"
git config --global user.email "YOUR_GITHUB_COMMIT_EMAIL"
git clone https://github.com/emrecandir9/JamScan.git
cd JamScan
```

For HTTPS authentication, use GitHub Desktop or Git Credential Manager. A
GitHub account password does not authenticate Git pushes; never paste a token
into a remote URL or a tracked file.

## Example: start S1-02

Start with a clean working tree (`git status` should show no pending changes):

```bash
git switch main
git pull --ff-only origin main
git switch -c feature/S1-02-navigation
```

Make changes, run the checks in [CONTRIBUTING.md](../CONTRIBUTING.md), then
review what you will upload:

```bash
git status
git diff
git add mobile/lib mobile/test
git diff --cached
git commit -m "feat: add navigation shell"
git push -u origin feature/S1-02-navigation
```

The `git add` paths are examples: select the files your task changed. Include
dependency files if you intentionally changed dependencies.

## Open and review the pull request

1. Open [JamScan on GitHub](https://github.com/emrecandir9/JamScan).
2. Select **Compare & pull request**, or **Pull requests → New pull request**.
3. Set **base: main** and **compare: your task branch**.
4. Use a title such as `S1-02: Add navigation shell` and fill in the template.
5. Use a draft PR if work is unfinished; mark it ready when it is testable.
6. Select a teammate in **Reviewers**. For S1-01, the entire team should inspect
   it; the proposed branch protection requires at least one approval.
7. The reviewer opens **Files changed**, reads the changes and validation,
   optionally checks out the branch, and selects **Review changes → Approve**
   or **Request changes**.
8. Push fixes to the same branch. The PR and automated checks update.
9. When checks pass, discussions are resolved, and approval is present,
   select **Squash and merge**, then delete the remote task branch.

A green check only means the automated commands passed. A reviewer checks
whether the change meets the story.

## After a merge

With a clean working tree:

```bash
git switch main
git pull --ff-only origin main
git fetch --prune
```

Create your next branch from this updated `main`. Old local branches can
remain until you are comfortable deleting them. Squash merging can make
`git branch -d` refuse deletion; do not force deletion unless you have
confirmed the work is on `main` and there are no unique local changes.

## When two people edit the same file

Coordinate before broad changes to shared files. If your PR needs the latest
`main`, first commit your work, then run this **on your task branch**:

```bash
git fetch origin
git merge origin/main
```

If Git reports conflicts, open the files listed by `git status`, agree on the
combined code with the other developer, remove the conflict markers, then:

```bash
git add path/to/resolved_file
git commit
git push
```

Replace the example path with the resolved file. Rerun checks. If you need to
stop a conflicted merge, use `git merge --abort`. Avoid `git reset --hard` as
a way to resolve conflicts; it can discard work.

## Team coordination

Use the story ID in branches and PR titles, agree who edits shared files,
and keep PRs small. Only move S1-01 to Done after its checklist is complete,
including GitHub configuration and teammate review.
