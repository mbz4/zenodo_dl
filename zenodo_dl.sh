#!/usr/bin/env bash
#
# zenodo_dl.sh — Download files from restricted Zenodo repositories
#
# Usage: ./zenodo_dl.sh [RECORD_ID]
#        If RECORD_ID is not provided, you will be prompted.
#
# Repository: https://github.com/mbz4/zenodo_dl
# License: Apache 2.0
#

set -euo pipefail

VERSION="1.2.0"
API_BASE="https://zenodo.org/api"
TOKEN_FILE="$HOME/.zenodo_token"
TOKEN=""
RECORD_ID=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

info()    { echo -e "${BLUE}ℹ${NC}  $*"; }
success() { echo -e "${GREEN}✓${NC}  $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
error()   { echo -e "${RED}✗${NC}  $*" >&2; }

cleanup() { TOKEN=""; }
trap cleanup EXIT

check_dependencies() {
    local missing=()
    for cmd in curl jq; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
        echo "  Install: sudo apt install ${missing[*]}"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Record ID
# -----------------------------------------------------------------------------

get_record_id() {
    if [[ -n "${1:-}" ]]; then
        RECORD_ID="$1"
        return 0
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Zenodo Record ID${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Enter the Zenodo record ID. You can find it in the URL:"
    echo ""
    echo "    https://zenodo.org/records/1234567"
    echo "                              └──────┘"
    echo "                              Record ID"
    echo ""
    echo "  For draft/restricted records, the URL may look like:"
    echo "    https://zenodo.org/uploads/1234567"
    echo ""
    
    while true; do
        read -rp "  Record ID: " RECORD_ID
        if [[ "$RECORD_ID" =~ ^[0-9]+$ ]]; then
            break
        else
            warn "Invalid ID. Please enter numbers only."
        fi
    done
}

# -----------------------------------------------------------------------------
# Instructions
# -----------------------------------------------------------------------------

show_instructions() {
    cat << 'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  HOW TO GET A ZENODO PERSONAL ACCESS TOKEN (PAT)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. Log in to Zenodo
     https://zenodo.org/login

  2. Go to Applications settings
     https://zenodo.org/account/settings/applications/

  3. Under "Personal access tokens", click "+ New token"

  4. Configure the token:
     • Name: Something descriptive (e.g., "zenodo-dl")
     • Scopes:
         ☑ deposit:read   ← Required for restricted/draft records
         ☐ deposit:write  ← Only if uploading (not needed here)

  5. Click "Create" and COPY THE TOKEN IMMEDIATELY
     (You won't be able to see it again!)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SECURE TOKEN STORAGE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  This script checks for tokens in order:

    1. $ZENODO_TOKEN environment variable (best for CI/scripts)
    2. ~/.zenodo_token file (convenient for repeated use)
    3. Interactive prompt (one-time use)

  Environment variable (session only):

      export ZENODO_TOKEN="your_token_here"
      zenodo-dl 1234567

  Secure dotfile:

      echo "your_token" > ~/.zenodo_token
      chmod 600 ~/.zenodo_token

  With GPG encryption:

      echo "your_token" | gpg -c -o ~/.zenodo_token.gpg
      export ZENODO_TOKEN=$(gpg -d ~/.zenodo_token.gpg 2>/dev/null)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
    read -rp "  Press Enter to continue..."
}

# -----------------------------------------------------------------------------
# Token handling
# -----------------------------------------------------------------------------

get_token() {
    if [[ -n "${ZENODO_TOKEN:-}" ]]; then
        TOKEN="$ZENODO_TOKEN"
        info "Using token from \$ZENODO_TOKEN"
        return 0
    fi

    if [[ -f "$TOKEN_FILE" ]]; then
        local perms
        perms=$(stat -c %a "$TOKEN_FILE" 2>/dev/null || stat -f %Lp "$TOKEN_FILE" 2>/dev/null)
        if [[ "$perms" != "600" ]]; then
            warn "Fixing insecure permissions on $TOKEN_FILE"
            chmod 600 "$TOKEN_FILE"
        fi
        TOKEN="$(cat "$TOKEN_FILE")"
        info "Using token from $TOKEN_FILE"
        return 0
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Token Required${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  No token found. Select option ${BOLD}0${NC} from the menu for setup instructions."
    echo ""
    echo "  Quick: https://zenodo.org/account/settings/applications/"
    echo "         → New token → check 'deposit:read' → Create → Copy"
    echo ""

    read -rsp "  Paste token (hidden): " TOKEN
    echo ""

    [[ -z "$TOKEN" ]] && { error "No token provided."; exit 1; }

    info "Validating..."
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        "$API_BASE/deposit/depositions/$RECORD_ID")

    if [[ "$http_code" != "200" ]]; then
        error "Validation failed (HTTP $http_code). Check token scope and record ID."
        TOKEN=""
        exit 1
    fi
    success "Token valid"
    echo ""

    read -rp "  Save to $TOKEN_FILE? [y/N]: " save
    if [[ "${save,,}" == "y" ]]; then
        echo "$TOKEN" > "$TOKEN_FILE"
        chmod 600 "$TOKEN_FILE"
        success "Saved (chmod 600)"
    fi
}

remove_token() {
    if [[ -f "$TOKEN_FILE" ]]; then
        rm -f "$TOKEN_FILE"
        success "Removed $TOKEN_FILE"
    else
        info "No stored token found"
    fi
}

# -----------------------------------------------------------------------------
# API
# -----------------------------------------------------------------------------

get_record_info() {
    local info
    info=$(curl -s -H "Authorization: Bearer $TOKEN" \
        "$API_BASE/deposit/depositions/$RECORD_ID" 2>/dev/null)
    if [[ -z "$info" ]] || echo "$info" | jq -e '.status == 404' &>/dev/null; then
        info=$(curl -s -H "Authorization: Bearer $TOKEN" \
            "$API_BASE/records/$RECORD_ID" 2>/dev/null)
    fi
    echo "$info"
}

list_files() {
    local info
    info=$(get_record_info)
    echo "$info" | jq -r '
        .files[] | 
        "\(.filesize // .size | tonumber | . / 1024 / 1024 * 100 | floor / 100) MB\t\(.filename // .key)"
    ' 2>/dev/null | sort -k2
}

get_file_list() {
    local info
    info=$(get_record_info)
    echo "$info" | jq -r '.files[].filename // .files[].key' 2>/dev/null
}

# -----------------------------------------------------------------------------
# Download
# -----------------------------------------------------------------------------

download_all() {
    echo ""
    echo "  Format:"
    echo "    1) ZIP archive (fast, single file)"
    echo "    2) Individual files (loose)"
    echo ""
    read -rp "  Choice [1]: " fmt
    fmt="${fmt:-1}"

    read -rp "  Output directory [.]: " outdir
    outdir="${outdir:-.}"
    outdir="${outdir/#\~/$HOME}"
    mkdir -p "$outdir"

    if [[ "$fmt" == "1" ]]; then
        local outfile="$outdir/zenodo_${RECORD_ID}.zip"
        info "Downloading to $outfile ..."

        curl -L -H "Authorization: Bearer $TOKEN" \
            "$API_BASE/records/$RECORD_ID/files-archive" \
            -o "$outfile" --progress-bar

        if file "$outfile" | grep -q "Zip archive"; then
            success "Downloaded: $outfile ($(du -h "$outfile" | cut -f1))"
            echo ""
            read -rp "  Extract? [y/N]: " extract
            if [[ "${extract,,}" == "y" ]]; then
                read -rp "  Extract to [.]: " exdir
                exdir="${exdir:-.}"
                unzip -o "$outfile" -d "$exdir"
                success "Extracted to $exdir"
            fi
        else
            error "Download failed:"
            cat "$outfile"
            rm -f "$outfile"
        fi
    else
        local files count i=1
        files=$(get_file_list)
        count=$(echo "$files" | grep -c . || echo 0)

        info "Downloading $count files to $outdir ..."
        echo ""

        while IFS= read -r filename; do
            [[ -z "$filename" ]] && continue
            printf "\r  [%d/%d] %-50s" "$i" "$count" "$filename"

            curl -sL -H "Authorization: Bearer $TOKEN" \
                "$API_BASE/deposit/depositions/$RECORD_ID/files/$filename/content" \
                -o "$outdir/$filename" 2>/dev/null || \
            curl -sL -H "Authorization: Bearer $TOKEN" \
                "$API_BASE/records/$RECORD_ID/files/$filename/content" \
                -o "$outdir/$filename"

            ((i++))
        done <<< "$files"

        echo ""
        success "Downloaded $count files"
    fi
}

download_specific() {
    local files i=1
    files=$(get_file_list)

    info "Available files:"
    echo ""
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        echo "  $i) $f"
        ((i++))
    done <<< "$files"

    echo ""
    read -rp "  File number(s) or pattern: " selection
    read -rp "  Output directory [.]: " outdir
    outdir="${outdir:-.}"
    outdir="${outdir/#\~/$HOME}"
    mkdir -p "$outdir"

    if [[ "$selection" =~ ^[0-9\ ]+$ ]]; then
        for num in $selection; do
            local filename
            filename=$(echo "$files" | sed -n "${num}p")
            if [[ -n "$filename" ]]; then
                info "Downloading $filename ..."
                curl -L -H "Authorization: Bearer $TOKEN" \
                    "$API_BASE/records/$RECORD_ID/files/$filename/content" \
                    -o "$outdir/$filename" --progress-bar 2>/dev/null || \
                curl -L -H "Authorization: Bearer $TOKEN" \
                    "$API_BASE/deposit/depositions/$RECORD_ID/files/$filename/content" \
                    -o "$outdir/$filename" --progress-bar
                success "$outdir/$filename"
            fi
        done
    else
        local matched=0
        while IFS= read -r filename; do
            [[ -z "$filename" ]] && continue
            if [[ "$filename" == *"$selection"* ]]; then
                info "Downloading $filename ..."
                curl -L -H "Authorization: Bearer $TOKEN" \
                    "$API_BASE/records/$RECORD_ID/files/$filename/content" \
                    -o "$outdir/$filename" --progress-bar 2>/dev/null || \
                curl -L -H "Authorization: Bearer $TOKEN" \
                    "$API_BASE/deposit/depositions/$RECORD_ID/files/$filename/content" \
                    -o "$outdir/$filename" --progress-bar
                success "$outdir/$filename"
                ((matched++))
            fi
        done <<< "$files"
        [[ $matched -eq 0 ]] && warn "No files matched: $selection"
    fi
}

# -----------------------------------------------------------------------------
# Extract
# -----------------------------------------------------------------------------

extract_archive() {
    echo ""
    read -rp "  Archive path: " archive
    archive="${archive/#\~/$HOME}"

    [[ ! -f "$archive" ]] && { error "Not found: $archive"; return 1; }

    read -rp "  Extract to [.]: " exdir
    exdir="${exdir:-.}"
    exdir="${exdir/#\~/$HOME}"
    mkdir -p "$exdir"

    local ftype
    ftype=$(file -b "$archive")

    if [[ "$ftype" == *"Zip"* ]]; then
        unzip -o "$archive" -d "$exdir"
    elif [[ "$ftype" == *"gzip"* ]] || [[ "$archive" == *.tar.gz ]] || [[ "$archive" == *.tgz ]]; then
        tar -xzf "$archive" -C "$exdir"
    elif [[ "$ftype" == *"tar"* ]] || [[ "$archive" == *.tar ]]; then
        tar -xf "$archive" -C "$exdir"
    else
        error "Unknown format: $ftype"
        return 1
    fi

    success "Extracted to $exdir"
}

# -----------------------------------------------------------------------------
# Menu
# -----------------------------------------------------------------------------

menu() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  zenodo-dl ${VERSION} — Record ${BOLD}${RECORD_ID}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "    0) Help — token setup instructions"
    echo "    1) List files"
    echo "    2) Download all"
    echo "    3) Download specific file(s)"
    echo "    4) Extract archive"
    echo ""
    echo "    t) Remove stored token"
    echo "    r) Change record ID"
    echo "    q) Quit"
    echo ""
    read -rp "  → " choice

    case "$choice" in
        0) show_instructions; menu ;;
        1) echo ""; list_files | column -t; menu ;;
        2) download_all; menu ;;
        3) download_specific; menu ;;
        4) extract_archive; menu ;;
        t|T) echo ""; remove_token; menu ;;
        r|R) get_record_id; get_token; menu ;;
        q|Q) echo ""; info "Bye!"; exit 0 ;;
        *) warn "Invalid option"; menu ;;
    esac
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    echo ""
    echo -e "${GREEN}┌─────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}│        zenodo_dl.sh ${VERSION}             │${NC}"
    echo -e "${GREEN}│   Download from Zenodo repositories     │${NC}"
    echo -e "${GREEN}└─────────────────────────────────────────┘${NC}"

    check_dependencies
    get_record_id "${1:-}"
    get_token
    menu
}

main "$@"