#!/usr/bin/env bash
#
# zenodo_dl.sh — Download files from Zenodo repositories
# https://github.com/mbz4/zenodo_dl
# License: Apache 2.0
#

set -euo pipefail

VERSION="1.3.0"
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

# -----------------------------------------------------------------------------
# CLI flags
# -----------------------------------------------------------------------------

show_help() {
    cat << EOF
zenodo_dl.sh v${VERSION} — Download files from Zenodo repositories

USAGE
    ./zenodo_dl.sh [RECORD_ID]     Interactive mode
    ./zenodo_dl.sh --help          Show this help
    ./zenodo_dl.sh --uninstall     Remove stored token (~/.zenodo_token)

EXAMPLES
    ./zenodo_dl.sh                 Prompt for record ID
    ./zenodo_dl.sh 18428827        Use record ID directly
    ZENODO_TOKEN=xyz ./zenodo_dl.sh 18428827   Pre-set token

RUN WITHOUT DOWNLOADING
    bash <(curl -fsSL https://raw.githubusercontent.com/mbz4/zenodo_dl/main/zenodo_dl.sh)

TOKEN
    For restricted/draft records, get a token from:
    https://zenodo.org/account/settings/applications/
    
    Required scope: deposit:read

MORE INFO
    https://github.com/mbz4/zenodo_dl
EOF
    exit 0
}

do_uninstall() {
    echo ""
    if [[ -f "$TOKEN_FILE" ]]; then
        rm -f "$TOKEN_FILE"
        success "Removed $TOKEN_FILE"
    else
        info "No token file found at $TOKEN_FILE"
    fi
    echo ""
    info "To fully remove zenodo_dl, just delete the script file."
    echo "    rm ./zenodo_dl.sh  (or wherever you saved it)"
    echo ""
    exit 0
}

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

check_dependencies() {
    local missing=()
    for cmd in curl jq; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing: ${missing[*]}"
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
    echo "  Find the record ID in the Zenodo URL:"
    echo ""
    echo "    https://zenodo.org/records/${BOLD}1234567${NC}"
    echo "    https://zenodo.org/uploads/${BOLD}1234567${NC}  (drafts)"
    echo ""

    while true; do
        read -rp "  Record ID: " RECORD_ID
        if [[ "$RECORD_ID" =~ ^[0-9]+$ ]]; then
            break
        else
            warn "Numbers only"
        fi
    done
}

# -----------------------------------------------------------------------------
# Token
# -----------------------------------------------------------------------------

show_token_help() {
    cat << 'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  HOW TO GET A ZENODO TOKEN
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. Log in:     https://zenodo.org/login
  2. Settings:   https://zenodo.org/account/settings/applications/
  3. Click:      + New token
  4. Scope:      ☑ deposit:read
  5. Create & copy immediately (shown only once)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  STORAGE OPTIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Environment variable (session):
      export ZENODO_TOKEN="your_token"

  Dotfile (persistent):
      echo "your_token" > ~/.zenodo_token && chmod 600 ~/.zenodo_token

  This script checks: $ZENODO_TOKEN → ~/.zenodo_token → prompt

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
    read -rp "  Press Enter to continue..."
}

get_token() {
    if [[ -n "${ZENODO_TOKEN:-}" ]]; then
        TOKEN="$ZENODO_TOKEN"
        info "Using \$ZENODO_TOKEN"
        return 0
    fi

    if [[ -f "$TOKEN_FILE" ]]; then
        local perms
        perms=$(stat -c %a "$TOKEN_FILE" 2>/dev/null || stat -f %Lp "$TOKEN_FILE" 2>/dev/null)
        if [[ "$perms" != "600" ]]; then
            chmod 600 "$TOKEN_FILE"
        fi
        TOKEN="$(cat "$TOKEN_FILE")"
        info "Using $TOKEN_FILE"
        return 0
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Token Required${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Get one: https://zenodo.org/account/settings/applications/"
    echo "  Select ${BOLD}0${NC} from menu for detailed instructions."
    echo ""

    read -rsp "  Token (hidden): " TOKEN
    echo ""

    [[ -z "$TOKEN" ]] && { error "No token"; exit 1; }

    info "Validating..."
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        "$API_BASE/deposit/depositions/$RECORD_ID")

    if [[ "$http_code" != "200" ]]; then
        error "Failed (HTTP $http_code)"
        TOKEN=""
        exit 1
    fi
    success "Valid"
    echo ""

    read -rp "  Save to $TOKEN_FILE? [y/N]: " save
    if [[ "${save,,}" == "y" ]]; then
        echo "$TOKEN" > "$TOKEN_FILE"
        chmod 600 "$TOKEN_FILE"
        success "Saved"
    fi
}

remove_token() {
    if [[ -f "$TOKEN_FILE" ]]; then
        rm -f "$TOKEN_FILE"
        success "Removed $TOKEN_FILE"
    else
        info "No stored token"
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
    get_record_info | jq -r '
        .files[] |
        "\(.filesize // .size | tonumber | . / 1024 / 1024 * 100 | floor / 100) MB\t\(.filename // .key)"
    ' 2>/dev/null | sort -k2
}

get_file_list() {
    get_record_info | jq -r '.files[].filename // .files[].key' 2>/dev/null
}

# -----------------------------------------------------------------------------
# Download
# -----------------------------------------------------------------------------

download_all() {
    echo ""
    echo "  1) ZIP (single file)"
    echo "  2) Individual files"
    echo ""
    read -rp "  Format [1]: " fmt
    fmt="${fmt:-1}"

    read -rp "  Output dir [.]: " outdir
    outdir="${outdir:-.}"
    outdir="${outdir/#\~/$HOME}"
    mkdir -p "$outdir"

    if [[ "$fmt" == "1" ]]; then
        local outfile="$outdir/zenodo_${RECORD_ID}.zip"
        info "Downloading $outfile ..."

        curl -L -H "Authorization: Bearer $TOKEN" \
            "$API_BASE/records/$RECORD_ID/files-archive" \
            -o "$outfile" --progress-bar

        if file "$outfile" | grep -q "Zip archive"; then
            success "Done: $outfile ($(du -h "$outfile" | cut -f1))"
            echo ""
            read -rp "  Extract? [y/N]: " ex
            if [[ "${ex,,}" == "y" ]]; then
                read -rp "  Extract to [.]: " exdir
                unzip -o "$outfile" -d "${exdir:-.}"
                success "Extracted"
            fi
        else
            error "Failed:"
            cat "$outfile"
            rm -f "$outfile"
        fi
    else
        local files count i=1
        files=$(get_file_list)
        count=$(echo "$files" | grep -c . || echo 0)

        info "Downloading $count files..."
        echo ""

        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            printf "\r  [%d/%d] %-45s" "$i" "$count" "$f"
            curl -sL -H "Authorization: Bearer $TOKEN" \
                "$API_BASE/deposit/depositions/$RECORD_ID/files/$f/content" \
                -o "$outdir/$f" 2>/dev/null || \
            curl -sL -H "Authorization: Bearer $TOKEN" \
                "$API_BASE/records/$RECORD_ID/files/$f/content" \
                -o "$outdir/$f"
            ((i++))
        done <<< "$files"

        echo ""
        success "Done: $count files"
    fi
}

download_specific() {
    local files i=1
    files=$(get_file_list)

    echo ""
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        echo "  $i) $f"
        ((i++))
    done <<< "$files"

    echo ""
    read -rp "  File number(s) or pattern: " sel
    read -rp "  Output dir [.]: " outdir
    outdir="${outdir:-.}"
    outdir="${outdir/#\~/$HOME}"
    mkdir -p "$outdir"

    if [[ "$sel" =~ ^[0-9\ ]+$ ]]; then
        for n in $sel; do
            local f
            f=$(echo "$files" | sed -n "${n}p")
            [[ -z "$f" ]] && continue
            info "$f ..."
            curl -L -H "Authorization: Bearer $TOKEN" \
                "$API_BASE/records/$RECORD_ID/files/$f/content" \
                -o "$outdir/$f" --progress-bar 2>/dev/null || \
            curl -L -H "Authorization: Bearer $TOKEN" \
                "$API_BASE/deposit/depositions/$RECORD_ID/files/$f/content" \
                -o "$outdir/$f" --progress-bar
            success "$outdir/$f"
        done
    else
        local matched=0
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            if [[ "$f" == *"$sel"* ]]; then
                info "$f ..."
                curl -L -H "Authorization: Bearer $TOKEN" \
                    "$API_BASE/records/$RECORD_ID/files/$f/content" \
                    -o "$outdir/$f" --progress-bar 2>/dev/null || \
                curl -L -H "Authorization: Bearer $TOKEN" \
                    "$API_BASE/deposit/depositions/$RECORD_ID/files/$f/content" \
                    -o "$outdir/$f" --progress-bar
                success "$outdir/$f"
                ((matched++))
            fi
        done <<< "$files"
        [[ $matched -eq 0 ]] && warn "No match: $sel"
    fi
}

extract_archive() {
    echo ""
    read -rp "  Archive path: " arch
    arch="${arch/#\~/$HOME}"
    [[ ! -f "$arch" ]] && { error "Not found"; return 1; }

    read -rp "  Extract to [.]: " exdir
    exdir="${exdir:-.}"
    mkdir -p "$exdir"

    local t
    t=$(file -b "$arch")
    if [[ "$t" == *"Zip"* ]]; then
        unzip -o "$arch" -d "$exdir"
    elif [[ "$t" == *"gzip"* || "$arch" == *.tar.gz || "$arch" == *.tgz ]]; then
        tar -xzf "$arch" -C "$exdir"
    elif [[ "$t" == *"tar"* || "$arch" == *.tar ]]; then
        tar -xf "$arch" -C "$exdir"
    else
        error "Unknown format"; return 1
    fi
    success "Extracted to $exdir"
}

# -----------------------------------------------------------------------------
# Menu
# -----------------------------------------------------------------------------

menu() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  zenodo_dl ${VERSION} — Record ${BOLD}${RECORD_ID}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "    0) Token help"
    echo "    1) List files"
    echo "    2) Download all"
    echo "    3) Download specific"
    echo "    4) Extract archive"
    echo ""
    echo "    t) Remove token    r) Change record    q) Quit"
    echo ""
    read -rp "  → " c

    case "$c" in
        0) show_token_help; menu ;;
        1) echo ""; list_files | column -t; menu ;;
        2) download_all; menu ;;
        3) download_specific; menu ;;
        4) extract_archive; menu ;;
        t|T) echo ""; remove_token; menu ;;
        r|R) get_record_id; get_token; menu ;;
        q|Q) echo ""; exit 0 ;;
        *) warn "Invalid"; menu ;;
    esac
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    # Handle flags
    case "${1:-}" in
        -h|--help) show_help ;;
        --uninstall) do_uninstall ;;
    esac

    echo ""
    echo -e "${GREEN}┌────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}│  zenodo_dl.sh ${VERSION}                  │${NC}"
    echo -e "${GREEN}└────────────────────────────────────────┘${NC}"

    check_dependencies
    get_record_id "${1:-}"
    get_token
    menu
}

main "$@"