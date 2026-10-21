#!/bin/bash
# Check for port updates by comparing Portfile versions with latest releases
# Usage: check-updates.sh [path/to/ports/directory]
#
# By default searches current directory for Portfiles.
# Supports:
#   - GitHub-hosted ports (github PortGroup)
#   - SVN-hosted ports (fetch.type svn) via SourceForge RSS feeds

REPO_ROOT="${1:-.}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if @trodemaster is a maintainer of this port *upstream*.
# The local Portfile is not authoritative: blakeports copies of ports we only
# test locally (qemu, lima, ...) may list @trodemaster, but the role that matters
# is the one in macports/macports-ports master. Local-only ports are skipped.
UPSTREAM_REPO="macports/macports-ports"
is_maintained_by_trodemaster() {
    local portfile="$1"
    local portdir=$(dirname "$portfile")
    local rel="$(basename "$(dirname "$portdir")")/$(basename "$portdir")/Portfile"
    gh api -H "Accept: application/vnd.github.raw" \
        "repos/${UPSTREAM_REPO}/contents/${rel}?ref=master" 2>/dev/null |
        grep -q "^maintainers.*@trodemaster\|^[[:space:]]*{.*@trodemaster"
}

# Function to extract github.setup from a Portfile
get_github_info() {
    local portfile="$1"

    # Check if it uses github PortGroup
    if ! grep -q "^PortGroup.*github" "$portfile"; then
        return 1
    fi

    # Extract github.setup line (may be indented)
    local setup_line=$(grep "github.setup" "$portfile" | grep -v "^#" | head -1)
    if [ -z "$setup_line" ]; then
        return 1
    fi

    # Parse: github.setup owner repo version [tag_prefix]
    local owner=$(echo "$setup_line" | awk '{print $2}')
    local repo=$(echo "$setup_line" | awk '{print $3}')
    local version=$(echo "$setup_line" | awk '{print $4}')
    local tag_prefix=$(echo "$setup_line" | awk '{print $5}')

    echo "$owner|$repo|$version|$tag_prefix"
}

# Function to get latest GitHub release
get_latest_release() {
    local owner="$1"
    local repo="$2"
    
    # Query GitHub API for latest release
    local api_url="https://api.github.com/repos/${owner}/${repo}/releases/latest"
    local response=$(curl -s -H "Accept: application/vnd.github.v3+json" "$api_url")
    
    # Check if we got a valid response
    if echo "$response" | grep -q '"tag_name"'; then
        echo "$response" | grep '"tag_name"' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/'
        return 0
    fi
    
    # If no releases, try tags
    api_url="https://api.github.com/repos/${owner}/${repo}/tags"
    response=$(curl -s -H "Accept: application/vnd.github.v3+json" "$api_url" | head -20)
    
    if echo "$response" | grep -q '"name"'; then
        echo "$response" | grep '"name"' | head -1 | sed -E 's/.*"name": "([^"]+)".*/\1/'
        return 0
    fi
    
    return 1
}

# Function to normalize version (strip common prefixes)
normalize_version() {
    local version="$1"
    local tag_prefix="$2"
    
    # Remove tag_prefix if specified
    if [ -n "$tag_prefix" ]; then
        version="${version#$tag_prefix}"
    fi
    
    # Remove common version prefixes
    version="${version#v}"
    version="${version#V}"
    version="${version#release-}"
    version="${version#version-}"
    
    echo "$version"
}

# Function to extract SVN info from a Portfile
get_svn_info() {
    local portfile="$1"
    
    # Check if it uses SVN
    if ! grep -q "^fetch.type.*svn" "$portfile"; then
        return 1
    fi
    
    # Extract svn.url, svn.revision, and version
    local svn_url=$(grep "^svn.url" "$portfile" | awk '{print $2}')
    local svn_revision=$(grep "^svn.revision" "$portfile" | awk '{print $2}')
    local version=$(grep "^version" "$portfile" | head -1 | awk '{print $2}')
    local name=$(grep "^name" "$portfile" | head -1 | awk '{print $2}')
    
    if [ -z "$svn_url" ] || [ -z "$svn_revision" ]; then
        return 1
    fi
    
    echo "$svn_url|$svn_revision|$version|$name"
}

# Function to get latest SVN release from SourceForge RSS feed
get_latest_svn_release() {
    local svn_url="$1"
    local port_name="$2"
    
    # Extract project name from SVN URL (e.g., previous from https://svn.code.sf.net/p/previous/code/trunk)
    local project=$(echo "$svn_url" | sed -n 's|.*svn.code.sf.net/p/\([^/]*\)/.*|\1|p')
    
    if [ -z "$project" ]; then
        return 1
    fi
    
    # Query SourceForge RSS feed for the project
    local rss_url="https://sourceforge.net/p/${project}/code/feed"
    local response=$(curl -s "$rss_url" 2>/dev/null)
    
    if [ -z "$response" ]; then
        return 1
    fi
    
    # Parse RSS feed for latest "Releasing" or "Updating trunk to version" commit
    # Format: <title>Updating version number. Releasing ProjectName vX.Y.</title>
    #    OR:  <title>Updating trunk to version X.Y.</title>
    #         <link>https://sourceforge.net/p/project/code/REVISION/</link>
    local result=$(echo "$response" | sed 's/></>\n</g' | \
        awk -v name="$port_name" '
            (/Releasing/ && tolower($0) ~ tolower(name)) || /Updating trunk to version|Updating version number/ {
                match($0, /v[0-9.]+|version [0-9.]+/)
                version = substr($0, RSTART, RLENGTH)
                gsub(/^v|^version /, "", version)
                gsub(/\.$/, "", version)
                getline
                match($0, /\/code\/([0-9]+)\//)
                revision = substr($0, RSTART+6, RLENGTH-7)
                print revision":"version
                exit
            }
        ')
    
    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi
    
    return 1
}

# Function to compare versions
version_compare() {
    local current="$1"
    local latest="$2"
    
    if [ "$current" = "$latest" ]; then
        echo "="
    else
        # Simple string comparison for now
        # Could be enhanced with proper semantic versioning
        if [ "$current" \< "$latest" ]; then
            echo "<"
        else
            echo ">"
        fi
    fi
}

echo "==========================================="
echo "Checking for port updates (ports where @trodemaster is an upstream maintainer)"
echo "==========================================="
echo ""

# Find all Portfiles
total=0
updates_available=0
up_to_date=0
errors=0
maintained_ports=()

while IFS= read -r portfile; do
    # Get port name from path
    portdir=$(dirname "$portfile")
    portname=$(basename "$portdir")
    category=$(basename "$(dirname "$portdir")")
    
    # Skip if in _resources or hidden directories
    if [[ "$portfile" == *"/_resources/"* ]] || [[ "$portfile" == */"./"* ]]; then
        continue
    fi
    
    # Skip ports not maintained by @trodemaster
    if ! is_maintained_by_trodemaster "$portfile"; then
        continue
    fi

    total=$((total + 1))
    maintained_ports+=("$portname")

    # Try GitHub first
    github_info=$(get_github_info "$portfile")
    if [ $? -eq 0 ]; then
        IFS='|' read -r owner repo current_version tag_prefix <<< "$github_info"
        
        # Get latest release
        latest_tag=$(get_latest_release "$owner" "$repo")
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}⚠${NC}  ${category}/${portname}: Could not fetch latest release from ${owner}/${repo}"
            errors=$((errors + 1))
            continue
        fi
        
        # Normalize versions for comparison
        current_norm=$(normalize_version "$current_version" "$tag_prefix")
        latest_norm=$(normalize_version "$latest_tag" "$tag_prefix")
        
        # Compare versions
        comparison=$(version_compare "$current_norm" "$latest_norm")
        
        if [ "$comparison" = "<" ]; then
            echo -e "${RED}✗${NC}  ${category}/${portname}: ${current_version} → ${latest_tag} ${BLUE}(update available)${NC}"
            echo "   GitHub: https://github.com/${owner}/${repo}"
            updates_available=$((updates_available + 1))
        elif [ "$comparison" = "=" ]; then
            echo -e "${GREEN}✓${NC}  ${category}/${portname}: ${current_version} (up to date)"
            up_to_date=$((up_to_date + 1))
        else
            echo -e "${YELLOW}?${NC}  ${category}/${portname}: ${current_version} vs ${latest_tag} (version mismatch?)"
            errors=$((errors + 1))
        fi
        continue
    fi
    
    # Try SVN
    svn_info=$(get_svn_info "$portfile")
    if [ $? -eq 0 ]; then
        IFS='|' read -r svn_url current_revision current_version port_name <<< "$svn_info"
        
        # Get latest release from SourceForge RSS
        latest_release=$(get_latest_svn_release "$svn_url" "$port_name")
        if [ $? -ne 0 ] || [ -z "$latest_release" ]; then
            echo -e "${YELLOW}⚠${NC}  ${category}/${portname}: Could not fetch latest release from SVN"
            errors=$((errors + 1))
            continue
        fi
        
        IFS=':' read -r latest_revision latest_version <<< "$latest_release"
        
        # Compare revisions
        if [ "$current_revision" -lt "$latest_revision" ]; then
            echo -e "${RED}✗${NC}  ${category}/${portname}: r${current_revision} (v${current_version}) → r${latest_revision} (v${latest_version}) ${BLUE}(update available)${NC}"
            echo "   SVN: ${svn_url}"
            updates_available=$((updates_available + 1))
        elif [ "$current_revision" -eq "$latest_revision" ]; then
            echo -e "${GREEN}✓${NC}  ${category}/${portname}: r${current_revision} (v${current_version}) (up to date)"
            up_to_date=$((up_to_date + 1))
        else
            echo -e "${YELLOW}?${NC}  ${category}/${portname}: r${current_revision} vs r${latest_revision} (ahead of release?)"
            errors=$((errors + 1))
        fi
        continue
    fi
    
done < <(find "$REPO_ROOT" -name "Portfile" -type f)

# Check macports-ports for PRs by others against our ports: all open PRs,
# plus PRs merged/closed in the last PR_DAYS days (the local Portfile may be
# stale after someone else's update lands upstream).
PR_REPO="macports/macports-ports"
PR_DAYS="${PR_DAYS:-45}"
pr_hits=0
if command -v gh >/dev/null 2>&1 && [ ${#maintained_ports[@]} -gt 0 ]; then
    echo ""
    echo "==========================================="
    echo "PRs against our ports (${PR_REPO})"
    echo "==========================================="
    me=$(gh api user --jq .login 2>/dev/null)
    while IFS= read -r name; do
        prs=$(gh pr list --repo "$PR_REPO" --state all --limit 30 \
            --search "${name} in:title" \
            --json number,title,author,state,url,updatedAt 2>/dev/null |
            jq -r --arg me "$me" --argjson days "$PR_DAYS" --arg name "$name" '
                .[]
                | select(.author.login != $me)
                | select(.title | ascii_downcase | test("(^|[^a-z0-9_-])" + $name + "([^a-z0-9_-]|$)"))
                | select(.state == "OPEN" or ((.updatedAt | fromdateiso8601) > (now - $days * 86400)))
                | "\(.state)\t#\(.number)\t\(.author.login)\t\(.title)\t\(.url)"')
        [ -z "$prs" ] && continue
        while IFS=$'\t' read -r state num author title url; do
            case "$state" in
                OPEN)   color="$RED" ;;
                MERGED) color="$YELLOW" ;;
                *)      color="$NC" ;;
            esac
            echo -e "${color}${state}${NC}  ${name} ${num} by ${author}: ${title}"
            echo "   ${url}"
            pr_hits=$((pr_hits + 1))
        done <<< "$prs"
    done < <(printf '%s\n' "${maintained_ports[@]}" | sort -u)
    [ $pr_hits -eq 0 ] && echo -e "${GREEN}✓${NC}  No open or recent PRs by others"
    echo "(MERGED = upstream changed; sync blakeports with macports-ports before the next bump)"
fi

echo ""
echo "==========================================="
echo "Summary"
echo "==========================================="
echo "Total ports checked: $total"
echo -e "${GREEN}Up to date:${NC} $up_to_date"
echo -e "${RED}Updates available:${NC} $updates_available"
echo -e "${YELLOW}Errors/Unable to check:${NC} $errors"
echo -e "${YELLOW}PRs by others:${NC} $pr_hits"
echo ""

if [ $updates_available -gt 0 ]; then
    echo "Run the following to update a port:"
    echo ""
    echo "For GitHub ports:"
    echo "  1. Edit category/portname/Portfile - update version"
    echo "  2. sudo port checksum category/portname"
    echo "  3. Update checksums in Portfile"
    echo "  4. Test: sudo port install -sv category/portname"
    echo ""
    echo "For SVN ports:"
    echo "  1. Edit category/portname/Portfile - update svn.revision and version"
    echo "  2. Test: sudo port install -sv category/portname"
    exit 0
else
    exit 0
fi
