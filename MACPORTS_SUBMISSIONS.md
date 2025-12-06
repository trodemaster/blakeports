# MacPorts Submissions Workflow

This document outlines the complete workflow for contributing ports to the MacPorts project via the blakeports development repository.

## Overview

Our workflow follows a three-stage process:
1. **Development** → Develop and test ports in blakeports
2. **Transfer** → Create properly formatted submissions in macports-ports fork
3. **Submission** → Create pull requests to upstream MacPorts

## Prerequisites

### Required Tools
- MacPorts installed and updated
- Git with SSH keys configured
- GitHub CLI (`gh`) installed and authenticated
- Access to multiple architectures (arm64/x86_64) for testing

### Repository Setup
- **blakeports**: Development and testing repository
- **macports-ports**: Local fork of https://github.com/macports/macports-ports

## Special Workflow: Port Consolidation

When consolidating multiple ports into a single port (e.g., netatalk + netatalk4 → netatalk with subports):

### Prerequisites
- Ensure the consolidated port works in blakeports first
- Test both the main port and subport functionality
- Verify that conflicts are properly set up between subports

### Workflow
1. **Develop consolidated port** in blakeports with subport structure
2. **Test thoroughly** with `port lint --nitpick` and build tests
3. **Create branch** in macports-ports: `category/portname-consolidate-ports`
4. **Copy updated Portfile** to macports-ports
5. **Remove obsolete directories/files** using `git rm`
6. **Commit with proper message** focusing on the update, not consolidation
7. **Create PR** with comprehensive description of changes

### Key Considerations
- **Subject line**: Focus on the update (e.g., "netatalk: update to 4.3.2") not the consolidation
- **Body details**: Describe the consolidation in bullet points
- **Ticket references**: Use "Closes:" for fixed tickets, "Please also close:" for others
- **Subport conflicts**: Ensure mutual conflicts are properly configured

## Stage 1: Development in blakeports

### 1.1 Port Creation
```bash
cd /Users/blake/code/blakeports
mkdir -p category/portname
# Create Portfile following MacPorts guidelines
```

### 1.2 Local Testing
```bash
# Strict lint check (catches more potential issues)
port lint --nitpick category/portname

# Fix any warnings reported by --nitpick flag before proceeding

# Build test
sudo port install category/portname

# Verify installation
port installed portname
```

### 1.3 Multi-Architecture Testing
Test on both architectures when possible:
- **arm64** (Apple Silicon): Primary development machine
- **x86_64** (Intel): Remote testing via `ssh darkstar`

### 1.4 Development Commit
Commit to blakeports for tracking:
```bash
git add category/portname/
git commit -m "portname: development version X.Y.Z"
```

## Stage 2: Transfer to macports-ports

### 2.1 Branch Creation
```bash
cd /Users/blake/code/macports-ports
git checkout master && git pull origin master
git checkout -b category/portname-new-port
```

**Branch Naming Conventions:**
- New ports: `category/portname-new-port`
- Updates: `category/portname-update-version`
- Fixes: `category/portname-fix-description`
- Port consolidation: `category/portname-consolidate-ports`

### 2.2 File Transfer
```bash
mkdir -p category/portname
cp -r /Users/blake/code/blakeports/category/portname/* category/portname/
```

**For Port Consolidation:**
When consolidating multiple ports into one:
```bash
# Copy the updated Portfile
cp /path/to/updated/Portfile category/portname/Portfile

# Remove obsolete directories and files
rm -rf category/obsolete-portname
rm -f category/portname/files/obsolete-file

# Stage changes
git add category/portname/Portfile
git rm -r category/obsolete-portname category/portname/files/obsolete-file
```

### 2.3 Verification
```bash
# Final lint check in macports-ports (basic check since --nitpick was done in blakeports)
port lint category/portname

# Should return: "0 errors and 0 warnings found"
```

### 2.4 Staging
```bash
git add category/portname/
```

## Stage 3: Proper Commit and Submission

### 3.1 MacPorts-Standard Commit

**Subject Line Requirements:**
- Format: `portname: new port, version X.Y.Z` or `portname: update to X.Y.Z`
- Maximum 55 characters (60 absolute maximum)
- Start with port name followed by colon
- **Avoid implementation details**: Don't use terms like "consolidate ports" in subject line
- **Keep it simple**: Focus on what the commit does, not how it does it

**Body Requirements:**
- Blank line after subject
- 72-character line wrapping
- Focus on functionality, not implementation
- Avoid mentioning: build systems, test frameworks, CI/CD
- Use bullet points for key features

**Examples:**

*New Port:*
```
bstring: new port, version 1.0.1

The Better String Library for C - a fork of Paul Hsieh's Better 
String Library providing comprehensive string functions for C 
programming with improved memory safety and performance.

* comprehensive string manipulation functions
* safer memory handling than standard C strings  
* improved performance over traditional string operations
* enhanced API for modern C development
```

*Port Update:*
```
libfido2: update to 1.16.0

* update to version 1.16.0
* update maintainer email address
```

*Port Consolidation:*
```
netatalk: update to 4.3.2

* combine netatalk and netatalk4 into single port with subports
* switch to GitHub source and Meson build system
* modernize dependencies and configuration
* remove unused netatalk4 port files

Closes: https://trac.macports.org/ticket/69609
Closes: https://trac.macports.org/ticket/36674  
Closes: https://trac.macports.org/ticket/36673
See: https://trac.macports.org/ticket/23313
```

Note: Use "Closes:" for tickets automatically fixed by this commit. Use "References:", "See:", or "Re:" for related tickets that need manual review or closure.

**Commit Message Guidelines:**
- **Never mention**: "update checksums" (always required, redundant)
- **Focus on**: meaningful changes that affect users
- **Keep concise**: avoid unnecessary technical details
- **Use proper ticket keywords**: Use "Closes:", "fixes:", "closes:", etc. to automatically close tickets that this commit fixes; use "References:", "See:", "Re:", etc. to reference related tickets without closing them
- **Reference full URLs**: Always use complete Trac ticket URLs, not just ticket numbers

### 3.2 Commit Command
```bash
git commit -m "Subject line

Body with proper formatting..."
```

### 3.3 Push to Fork
```bash
git push origin category/portname-new-port
```

## Stage 4: Pull Request Creation

### 4.1 Gather System Information

**Local System (arm64):**
```bash
sw_vers                    # macOS version
uname -m                   # Architecture
xcodebuild -version        # Xcode version
pkgutil --pkg-info=com.apple.pkg.CLTools_Executables  # CLT version
port version               # MacPorts version
```

**Remote System (x86_64):**
```bash
ssh darkstar sw_vers
ssh darkstar uname -m
ssh darkstar "pkgutil --pkg-info=com.apple.pkg.CLTools_Executables"
ssh darkstar port version
```

### 4.2 Create Pull Request

**For Port Updates:**
```bash
gh pr create --repo macports/macports-ports --title "portname: update to X.Y.Z" --body "$(cat << 'EOF'
### Testing Performed

- [x] Port builds successfully locally
- [x] Port lint passes with 0 errors and 0 warnings
- [x] Dependencies verified
- [x] Installation tested

**Tested on**

macOS X.Y.Z Xcode A.B / Build version XXX (arm64)
EOF
)"
```

**For New Ports:**
```bash
gh pr create --repo macports/macports-ports --title "portname: new port, version X.Y.Z" --body "$(cat << 'EOF'
### Description

Brief description of what the software does and its key benefits.

### Key Features

* Feature 1
* Feature 2
* Feature 3
* Feature 4

### Testing Performed

- [x] Port builds successfully locally
- [x] Port lint passes with 0 errors and 0 warnings
- [x] Dependencies verified
- [x] Installation tested

**Tested on**

macOS X.Y.Z Xcode A.B / Build version XXX (arm64)
EOF
)"
```

### PR Content Guidelines
- **For Updates**: Keep it minimal - just show testing checklist
- **For New Ports**: Include description and key features
- **Do NOT mention**: checksums (always updated, redundant)
- **Do NOT mention**: internal development repos (blakeports, etc.)
- **Do NOT mention**: --nitpick flag (internal process)
- **Do NOT mention**: port categories, versions, or maintainer info (obvious from Portfile)
- **Focus on**: what matters to users
- **Keep professional**: avoid implementation details

## Stage 5: Post-Submission Monitoring

### 5.1 PR Monitoring
- Monitor the PR at the returned URL
- Respond promptly to maintainer feedback
- Address any requested changes

### 5.2 Common Review Feedback
- **Linting issues**: Run `port lint` and fix warnings
- **Build failures**: Test on additional architectures
- **Dependency issues**: Verify all dependencies are correct
- **Licensing**: Ensure license is properly specified
- **Documentation**: Add or improve port descriptions

### 5.3 Making Updates
If changes are requested:
```bash
# Make changes to Portfile
git add category/portname/
git commit -m "portname: address reviewer feedback"
git push origin category/portname-new-port
```

The PR will automatically update with new commits.

### 5.4 Updating Existing PRs and Squashing Commits

When you need to update an existing PR with fixes or improvements:

#### 5.4.1 Making Changes to Existing PR
```bash
cd /Users/blake/code/macports-ports
git checkout your-branch-name

# Make your changes to the Portfile
# Edit the Portfile as needed

# Stage and commit changes
git add category/portname/
git commit -m "portname: fix linting issues"
```

#### 5.4.2 Squashing Multiple Commits
If you have multiple commits that should be combined into one:

```bash
# Check current commit history
git log --oneline -5

# Soft reset to combine the last N commits (replace N with number of commits to squash)
git reset --soft HEAD~N

# Commit with the desired message (keep existing message if appropriate)
git commit -m "portname: update to X.Y.Z"

# Force push to update the PR
git push origin your-branch-name --force
```

#### 5.4.3 Preserving Existing Commit Messages
When updating a PR, you often want to keep the original commit message:
```bash
# After making changes and staging them
git commit -m "portname: update to 4.3.2"  # Use same message as original

# Force push to update PR
git push origin your-branch-name --force
```

#### 5.4.4 Complete Update Workflow Example
```bash
# 1. Switch to your PR branch
cd /Users/blake/code/macports-ports
git checkout net/netatalk-consolidate-ports

# 2. Make changes (edit Portfile, fix linting, etc.)
# Edit files as needed

# 3. Stage changes
git add category/portname/

# 4. If you have multiple commits to squash:
git reset --soft HEAD~2  # Squash last 2 commits
git commit -m "portname: update to X.Y.Z"  # Use original message

# 5. Force push to update PR
git push origin net/netatalk-consolidate-ports --force
```

#### 5.4.5 Best Practices for PR Updates
- **Keep commit messages consistent**: Use the same subject line as the original commit
- **Squash related commits**: Combine multiple small fixes into single logical commits
- **Test before pushing**: Always run `port lint --nitpick` before updating PR
- **Use force push carefully**: Only force push to your own feature branches, never to shared branches
- **Document changes**: Update PR description if significant changes are made

#### 5.4.6 When to Squash Commits
- **Multiple small fixes**: Combine several "fix typo" or "address feedback" commits
- **Clean up development history**: Remove "WIP" or "debug" commits before final submission
- **Maintainer requests**: When reviewers ask for cleaner commit history
- **Before final review**: Ensure PR has clean, logical commit structure

#### 5.4.7 Verifying PR Updates
After updating a PR, verify the changes:
```bash
# Check commit history is clean
git log --oneline -3

# Verify the PR shows updated files
# Check GitHub PR page for updated diff

# Confirm all changes are included
git show --stat HEAD
```

## Reference Links

### MacPorts Documentation
- [Commit Message Guidelines](https://trac.macports.org/wiki/CommitMessages)
- [Portfile Development Guide](https://guide.macports.org/#development)
- [MacPorts Guide](https://guide.macports.org/)

### Repositories
- **Upstream**: https://github.com/macports/macports-ports
- **Your Fork**: https://github.com/trodemaster/macports-ports
- **Development**: https://github.com/trodemaster/blakeports

## Examples

### Example 1: bstring Port Update

**Successfully submitted as**: https://github.com/macports/macports-ports/pull/30370

**Branch**: `textproc/bstring-update-1.0.3`

**PR Content**: Simple testing checklist following the simplified update template

**Testing Environment**:
- macOS 26.1 Xcode 26.1 / Build version 17B55 (arm64)

This example demonstrates the simplified workflow for port updates - keep PR body minimal with just testing details.

### Example 2: netatalk Port Consolidation

**Successfully submitted as**: https://github.com/macports/macports-ports/pull/29293

**Branch**: `net/netatalk-consolidate-ports`

**Testing Environment**:
- macOS 15.6.1 Xcode 16.4 / Command Line Tools 16.4.0.0.1.1747106510 (arm64)

This example demonstrates port consolidation, updating to a new upstream maintainer, and addressing multiple long-standing tickets in a single PR.

### Example 3: Updating Existing PR with Linting Fixes

**PR**: https://github.com/macports/macports-ports/pull/29293

**Scenario**: After initial PR submission, linting issues were discovered that needed to be fixed.

**Process**:
1. **Fixed in blakeports first**: Made all linting corrections in development repo
2. **Verified fixes**: Ran `port lint --nitpick` on all subports (netatalk, netatalk2, netatalk4)
3. **Updated macports-ports**: Copied fixed Portfile to PR branch
4. **Squashed commits**: Combined multiple fix commits into single clean commit
5. **Preserved message**: Kept original commit message "netatalk: update to 4.3.2"
6. **Force pushed**: Updated PR with clean history

**Commands used**:
```bash
# Fix in blakeports
cd /Users/blake/code/blakeports
# Edit Portfile, fix linting issues
port lint --nitpick net/netatalk

# Update macports-ports PR
cd /Users/blake/code/macports-ports
git checkout net/netatalk-consolidate-ports
# Copy fixed Portfile
git add net/netatalk/Portfile
git commit -m "netatalk: fix linting issues"

# Squash commits
git reset --soft HEAD~2
git commit -m "netatalk: update to 4.3.2"
git push origin net/netatalk-consolidate-ports --force
```

This example demonstrates the complete workflow for updating an existing PR with fixes while maintaining clean commit history.

## Troubleshooting

### Common Issues
1. **Port lint --nitpick warnings**: Address all style and best practice issues in blakeports
2. **Port lint failures**: Fix Portfile syntax and style issues
3. **Build failures**: Check dependencies and configure options
4. **Checksum mismatches**: Update checksums with `port checksum`
5. **Branch conflicts**: Rebase against updated master
6. **Commit message too long**: Keep subject line under 55 characters, move details to body
7. **Implementation details in subject**: Focus on what changed, not how it changed
8. **Missing ticket references**: Always include full URLs for referenced tickets

### PR Update Issues
9. **Multiple commits in PR**: Use `git reset --soft HEAD~N` to squash commits
10. **Force push rejected**: Ensure you're pushing to your own fork, not upstream
11. **Lost changes after squash**: Use `git reflog` to recover lost commits
12. **Wrong commit message**: Use `git commit --amend` for the last commit, or squash and recommit
13. **PR not updating**: Check that you're on the correct branch and pushed to the right remote
14. **Merge conflicts in PR**: Rebase against updated master: `git rebase origin/master`

### Getting Help
- MacPorts mailing lists
- IRC: #macports on Libera.Chat
- Trac tickets for bug reports
- GitHub discussions for questions

---

*Last updated: January 8, 2025*
*Workflow established for blakeports → macports-ports contribution process*
*Updated with port consolidation guidelines and commit message best practices*
