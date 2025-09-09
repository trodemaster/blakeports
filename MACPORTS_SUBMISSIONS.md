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
Please also close: https://trac.macports.org/ticket/23313 as the solution is in the new docs
```

**Commit Message Guidelines:**
- **Never mention**: "update checksums" (always required, redundant)
- **Focus on**: meaningful changes that affect users
- **Keep concise**: avoid unnecessary technical details
- **Use proper ticket keywords**: "Closes:" for tickets that are fixed, "Please also close:" for tickets that should be closed for other reasons
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
```bash
gh pr create --repo macports/macports-ports --title "portname: new port, version X.Y.Z" --body "$(cat << 'EOF'
## New Port Submission

This PR adds a new port for [portname] version [X.Y.Z] to the [category] category.

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

### PR Content Guidelines
- **Do NOT mention**: checksums (always updated, redundant)
- **Do NOT mention**: internal development repos (blakeports, etc.)
- **Do NOT mention**: --nitpick flag (internal process)
- **Focus on**: what changed, why it matters to users
- **Keep professional**: avoid implementation details
- **Use proper ticket references**: Include full URLs for all referenced tickets
- **Format URLs as clickable links**: Use markdown format for better readability

**Tested on**

macOS X.Y.Z Xcode A.B / Command Line Tools A.B.C.D.E.F (arm64)
macOS X.Y.Z Command Line Tools A.B.C.D.E.F (x86_64)

### Port Details
- **Category**: category
- **Version**: X.Y.Z
- **Homepage**: https://...
- **License**: LICENSE
- **Dependencies**: dep1, dep2, dep3

### Maintainer
@yourusername (openmaintainer)
EOF
)"
```

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

### Example 1: bstring Port Submission

**Successfully submitted as**: https://github.com/macports/macports-ports/pull/29227

**Branch**: `textproc/bstring-new-port`

**Testing Environment**:
- macOS 15.6.1 Xcode 16.4 / Command Line Tools 16.4.0.0.1.1747106510 (arm64)
- macOS 15.6.1 Command Line Tools 16.4.0.0.1.1747106510 (x86_64)

This example demonstrates the complete workflow from development through successful PR submission.

### Example 2: netatalk Port Consolidation

**Successfully submitted as**: https://github.com/macports/macports-ports/pull/29293

**Branch**: `net/netatalk-consolidate-ports`

**Testing Environment**:
- macOS 15.6.1 Xcode 16.4 / Command Line Tools 16.4.0.0.1.1747106510 (arm64)

This example demonstrates port consolidation, updating to a new upstream maintainer, and addressing multiple long-standing tickets in a single PR.

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

### Getting Help
- MacPorts mailing lists
- IRC: #macports on Libera.Chat
- Trac tickets for bug reports
- GitHub discussions for questions

---

*Last updated: January 8, 2025*
*Workflow established for blakeports → macports-ports contribution process*
*Updated with port consolidation guidelines and commit message best practices*
