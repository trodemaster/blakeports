# MacPorts Pull Request Template

This is the official PR template from macports-ports repository.
Use this as the starting point for all MacPorts PRs.

```markdown
#### Description

<!-- Note: it is best to make pull requests from a branch rather than from master -->

###### Type(s)
<!-- update (title contains ": U(u)pdate to"), submission (new Portfile) and CVE Identifiers are auto-detected, replace [ ] with [x] to select -->

- [ ] bugfix
- [ ] enhancement
- [ ] security fix

###### Tested on
<!-- Triple-click and copy the next line and paste it into your shell. It will copy your OS and Xcode version to the clipboard. Paste it here replacing this section.
sh -c 'echo "macOS $(sw_vers -productVersion) $(sw_vers -buildVersion) $(uname -m)"; xcode=$(xcodebuild -version 2>/dev/null); if [ $? == 0 ]; then echo "$(echo "$xcode" | awk '\''NR==1{x=$0}END{print x" "$NF}'\'')"; else echo "Command Line Tools $(pkgutil --pkg-info=com.apple.pkg.CLTools_Executables | awk '\''/version:/ {print $2}'\'')"; fi' | tee /dev/tty | pbcopy
-->
macOS x.y
Xcode x.y / Command Line Tools x.y.z

###### Verification <!-- (delete not applicable items) -->
Have you

- [ ] followed our [Commit Message Guidelines](https://trac.macports.org/wiki/CommitMessages)?
- [ ] squashed and [minimized your commits](https://guide.macports.org/#project.github)?
- [ ] checked that there aren't other open [pull requests](https://github.com/macports/macports-ports/pulls) for the same change?
- [ ] referenced existing tickets on [Trac](https://trac.macports.org/wiki/Tickets) with full URL in commit message? <!-- Please don't open a new Trac ticket if you are submitting a pull request. -->
- [ ] checked your Portfile with `port lint`?
- [ ] tried existing tests with `sudo port test`?
- [ ] tried a full install with `sudo port -vs install`?
- [ ] tested basic functionality of all binary files?
- [ ] checked that the Portfile's most important [variants](https://trac.macports.org/wiki/Variants) haven't been broken?

<!-- Use "skip notification" (surrounded with []) to avoid notifying maintainers -->
```

## "Tested on" System Info — Extract from CI Logs

**Always extract system info from the CI runner logs**, not from the local machine.
This ensures "Tested on" reflects the actual build environments.

After a successful CI run, fetch the "Gather system information" output for each job:

```bash
# Get job IDs from the run
gh --repo trodemaster/blakeports run view <run-id>

# Extract system info from each job log
gh --repo trodemaster/blakeports run view --job=<job-id> --log \
  | grep -E "Operating System|Architecture|Xcode Version|Command Line Tools" \
  | grep -v '^\[' | head -8
```

The output will contain lines like:
```
Operating System: macOS 15.6.1 (Build 24G90)
Architecture: arm64
Xcode Version: 26.3
Command Line Tools: 16.4.0.0.1.1747106510
```

Format each runner as one line in the PR:
```
macOS 15.6.1 24G90 arm64 / Xcode 26.3
macOS 26.4 25E246 arm64 / Xcode 26.4.1
```

List all runners that ran (typically macOS_15 and macOS_26).

## Notes

- **"update" and "submission" types are auto-detected** from PR title
- **CVE identifiers are auto-detected** from commit messages
- **Omit entire Type(s) section if none apply** - only include if bugfix/enhancement/security fix is checked
- Always make PRs from a feature branch, not from master
- Delete non-applicable verification items
- Use `[skip notification]` in PR body to avoid notifying maintainers (if needed)
