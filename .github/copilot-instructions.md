# Copilot Instructions — GitHub Copilot Chat Exporter

## Git Safety Rules (MANDATORY)

These rules apply to ALL git operations in this repository. No exceptions.

### Branch Switching

1. **NEVER run `git checkout` or `git switch` to change branches without explicit user confirmation.**
2. **Before proposing a branch switch, ALWAYS:**
   - Run `git status` to check for uncommitted/untracked files
   - Check if untracked files conflict with the target branch: `git ls-tree -r --name-only <target-branch>`
   - Explain what files will be **added or removed from disk** by the switch
   - Warn the user clearly: "Switching from X to Y will remove these files from disk: [list]. They are safe in git but will not be visible in your editor until you switch back."
3. **Prefer alternatives to branch switching:**
   - Use **GitHub PRs** for merging branches — no local switching needed
   - Use **`git worktree`** if you must work on two branches simultaneously
   - Never switch away from the user's active working branch without discussing trade-offs first

### Destructive Operations

4. **NEVER run these without explicit user confirmation AND explanation of consequences:**
   - `git checkout <branch>` (switches branches, removes/adds files on disk)
   - `git reset --hard` (discards uncommitted changes permanently)
   - `git clean -fd` (deletes untracked files permanently)
   - `git rebase` (rewrites commit history)
   - `git push --force` (overwrites remote history)
   - `git branch -D` (deletes a branch with unmerged commits)

5. **Safe alternatives to prefer:**
   - `git branch -d` over `git branch -D` (won't delete unmerged branches)
   - `git stash` before switching branches (preserves uncommitted work)
   - `git merge --no-ff` for explicit merge commits
   - PRs on GitHub over local merges

### Pre-Flight Checks

6. **Before ANY git write operation** (commit, merge, push, checkout, rebase):
   - Run `git status` to confirm state
   - Run `git stash list` if switching context
   - Verify the current branch with `git branch --show-current`
   - If untracked files exist, check for conflicts with the target

### Recovery

7. **If a git operation fails or leaves things in a bad state:**
   - Immediately run `git status` to assess
   - Restore missing files with `git checkout -- <file>` before doing anything else
   - Explain to the user what happened and why
   - Never silently proceed past a failed git operation

## Project Context

- **Active development branch:** `dev/v2`
- **Stable release branch:** `main` (v1.0.0)
- **The user is learning git workflows** — always explain what git commands do and why, especially operations that affect files on disk
- **v2 is being vetted** before merging to main — do not merge `dev/v2` to `main` without explicit instruction

## Testing & Validation

After any changes to the exporter scripts:
- Confirm the script parses without errors: `pwsh -NoProfile -Command "& { . '.\Save-CopilotChat-v2.ps1' -List }"`
- Verify git state is clean after commits: `git status` should show no unexpected changes
