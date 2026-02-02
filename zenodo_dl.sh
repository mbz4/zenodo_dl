#!/usr/bin/env bash
#
# zenodo_dl.sh — Download files from Zenodo repositories
# https://github.com/mbz4/zenodo_dl
# License: Apache 2.0
#

set -euo pipefail

VERSION="1.4.4"
API_BASE="https://zenodo.org/api"
TOKEN_FILE="$HOME/.zenodo_token"
TOKEN_FILE_ENC="$HOME/.zenodo_token.enc"
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

# Expand ~ and validate path
resolve_path() {
    local path="$1"
    path="${path/#\~/$HOME}"
    path="${path%/}"  # Remove trailing slash
    
    # Empty or current dir - return as-is
    [[ -z "$path" || "$path" == "." ]] && { echo "."; return; }
    
    # If absolute path and parent doesn't exist, offer alternatives
    if [[ "$path" =~ ^/ ]] && [[ ! -d "$(dirname "$path")" ]]; then
        local basename="${path#/}"
        echo -e "${YELLOW}⚠${NC}  '$path' requires root. Did you mean:" >&2
        echo "      1) ./$basename (relative to current dir)" >&2
        echo "      2) ~/$basename (in home dir)" >&2
        echo "      3) Keep as-is" >&2
        read -rp "  Choice [1]: " fix </dev/tty
        fix="${fix:-1}"
        case "$fix" in
            1) path="./$basename" ;;
            2) path="$HOME/$basename" ;;
            *) ;;
        esac
    fi
    
    echo "$path"
}

# -----------------------------------------------------------------------------
# CLI flags
# -----------------------------------------------------------------------------

show_help() {
    cat << EOF
zenodo_dl.sh v${VERSION} — Download files from Zenodo repositories

USAGE
    ./zenodo_dl.sh [RECORD_ID]     Interactive mode
    ./zenodo_dl.sh --help          Show this help
    ./zenodo_dl.sh --uninstall     Remove stored token(s)

EXAMPLES
    ./zenodo_dl.sh                 Prompt for record ID
    ./zenodo_dl.sh 12345678        Use record ID directly
    ZENODO_TOKEN=xyz ./zenodo_dl.sh 12345678   Pre-set token

RUN WITHOUT DOWNLOADING
    bash <(curl -fsSL https://raw.githubusercontent.com/mbz4/zenodo_dl/main/zenodo_dl.sh)

TOKEN STORAGE
    Tokens can be stored encrypted (AES-256, passphrase required each use)
    or plaintext (chmod 600). Encrypted is the default.

    Files: ~/.zenodo_token.enc (encrypted) or ~/.zenodo_token (plaintext)

MORE INFO
    https://github.com/mbz4/zenodo_dl
EOF
    exit 0
}

do_uninstall() {
    echo ""
    local removed=0
    if [[ -f "$TOKEN_FILE_ENC" ]]; then
        rm -f "$TOKEN_FILE_ENC"
        success "Removed $TOKEN_FILE_ENC"
        ((removed++)) || true
    fi
    if [[ -f "$TOKEN_FILE" ]]; then
        rm -f "$TOKEN_FILE"
        success "Removed $TOKEN_FILE"
        ((removed++)) || true
    fi
    if [[ $removed -eq 0 ]]; then
        info "No token files found"
    fi
    echo ""
    info "To fully remove, delete the script: rm ./zenodo_dl.sh"
    echo ""
    exit 0
}

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

check_dependencies() {
    local missing=()
    for cmd in curl jq openssl; do
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
    echo -e "    https://zenodo.org/records/${BOLD}1234567${NC}"
    echo -e "    https://zenodo.org/uploads/${BOLD}1234567${NC}  (drafts)"
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
# Token encryption
# -----------------------------------------------------------------------------

encrypt_token() {
    local token="$1"
    local passphrase="$2"
    echo "$token" | openssl enc -aes-256-cbc -pbkdf2 -salt -pass pass:"$passphrase" -base64
}

decrypt_token() {
    local passphrase="$1"
    openssl enc -aes-256-cbc -pbkdf2 -d -salt -pass pass:"$passphrase" -base64 < "$TOKEN_FILE_ENC" 2>/dev/null
}

save_token_encrypted() {
    local token="$1"
    echo ""
    while true; do
        read -rsp "  Create passphrase: " pass1
        echo ""
        read -rsp "  Confirm passphrase: " pass2
        echo ""
        if [[ "$pass1" == "$pass2" ]]; then
            if [[ -z "$pass1" ]]; then
                warn "Passphrase cannot be empty"
            else
                break
            fi
        else
            warn "Passphrases don't match"
        fi
    done

    encrypt_token "$token" "$pass1" > "$TOKEN_FILE_ENC"
    chmod 600 "$TOKEN_FILE_ENC"
    success "Saved encrypted to $TOKEN_FILE_ENC"
}

save_token_plaintext() {
    local token="$1"
    echo "$token" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    success "Saved to $TOKEN_FILE (plaintext, chmod 600)"
}

load_token_encrypted() {
    local attempts=0
    while [[ $attempts -lt 3 ]]; do
        read -rsp "  Passphrase: " pass
        echo ""
        TOKEN=$(decrypt_token "$pass" || echo "")
        if [[ -n "$TOKEN" ]]; then
            success "Token decrypted"
            return 0
        fi
        ((attempts++)) || true
        warn "Wrong passphrase ($attempts/3)"
    done
    error "Too many attempts"
    exit 1
}

# -----------------------------------------------------------------------------
# Token handling
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

  This script checks for tokens in order:

    1. $ZENODO_TOKEN environment variable
    2. ~/.zenodo_token.enc (encrypted, passphrase required)
    3. ~/.zenodo_token (plaintext, chmod 600)
    4. Interactive prompt

  Encrypted storage uses AES-256-CBC with PBKDF2 key derivation.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
    read -rp "  Press Enter to continue..."
}

get_token() {
    # 1. Environment variable
    if [[ -n "${ZENODO_TOKEN:-}" ]]; then
        TOKEN="$ZENODO_TOKEN"
        info "Using \$ZENODO_TOKEN"
        return 0
    fi

    # 2. Encrypted file
    if [[ -f "$TOKEN_FILE_ENC" ]]; then
        info "Found encrypted token"
        load_token_encrypted
        return 0
    fi

    # 3. Plaintext file
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

    # 4. Prompt
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Token Required${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Get one: https://zenodo.org/account/settings/applications/"
    echo "  Select ${BOLD}0${NC} from menu for detailed help."
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

    echo "  Save token?"
    echo "    1) Encrypted (passphrase each use) ${GREEN}← recommended${NC}"
    echo "    2) Plaintext (chmod 600)"
    echo "    3) Don't save"
    echo ""
    read -rp "  Choice [1]: " save_choice
    save_choice="${save_choice:-1}"

    case "$save_choice" in
        1) save_token_encrypted "$TOKEN" ;;
        2) save_token_plaintext "$TOKEN" ;;
        3) info "Token not saved" ;;
        *) save_token_encrypted "$TOKEN" ;;
    esac
}

remove_token() {
    local removed=0
    if [[ -f "$TOKEN_FILE_ENC" ]]; then
        rm -f "$TOKEN_FILE_ENC"
        success "Removed $TOKEN_FILE_ENC"
        ((removed++)) || true
    fi
    if [[ -f "$TOKEN_FILE" ]]; then
        rm -f "$TOKEN_FILE"
        success "Removed $TOKEN_FILE"
        ((removed++)) || true
    fi
    [[ $removed -eq 0 ]] && info "No stored token"
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
    outdir=$(resolve_path "$outdir")
    mkdir -p "$outdir" || { error "Cannot create directory"; return 1; }

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
    files=$(get_file_list | sort)

    echo ""
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        echo "  $i) $f"
        ((i++))
    done <<< "$files"

    echo ""
    read -rp "  File number(s) or pattern: " sel
    # Strip surrounding quotes if present
    sel="${sel#\"}"
    sel="${sel%\"}"
    sel="${sel#\'}"
    sel="${sel%\'}"
    read -rp "  Output dir [.]: " outdir
    outdir="${outdir:-.}"
    outdir=$(resolve_path "$outdir")
    mkdir -p "$outdir" || { error "Cannot create directory"; return 1; }

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
                ((matched++)) || true
            fi
        done <<< "$files"
        [[ $matched -eq 0 ]] && warn "No match: $sel"
    fi
}

extract_archive() {
    echo ""
    read -rp "  Archive path: " arch
    arch=$(resolve_path "$arch")
    [[ ! -f "$arch" ]] && { error "Not found: $arch"; return 1; }

    read -rp "  Extract to [.]: " exdir
    exdir="${exdir:-.}"
    exdir=$(resolve_path "$exdir")
    mkdir -p "$exdir" || { error "Cannot create directory"; return 1; }

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