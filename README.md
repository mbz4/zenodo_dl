# zenodo-dl

A simple CLI tool to download files from Zenodo repositories, including restricted/draft records using Zenodo Personal Access Tokens.

## Features

- Download from **public, restricted, or draft** Zenodo records
- Interactive menu or scriptable with arguments
- Secure token handling (environment variable, dotfile, or prompt)
- Download as ZIP or individual files
- Pattern matching for selective downloads
- Built-in archive extraction

## Requirements

- `curl`
- `jq`

Most Linux distributions have these pre-installed. If not:

```bash
# Debian/Ubuntu
sudo apt install curl jq

# Fedora
sudo dnf install curl jq

# macOS
brew install curl jq
```

## Installation

**One-liner:**

```bash
sudo curl -fsSL https://raw.githubusercontent.com/mbz4/zenodo-dl/main/zenodo-dl -o /usr/local/bin/zenodo-dl && sudo chmod +x /usr/local/bin/zenodo-dl
```

**Or manually:**

```bash
git clone https://github.com/YOUR_USERNAME/zenodo-dl.git
cd zenodo-dl
chmod +x zenodo-dl
sudo mv zenodo-dl /usr/local/bin/  # or add to PATH
```

**Or just run directly:**

```bash
curl -fsSL https://raw.githubusercontent.com/mbz4/zenodo-dl/main/zenodo-dl | bash -s -- 1234567
```

## Usage

```bash
# Interactive mode
zenodo-dl

# With record ID
zenodo-dl 1234567

# With pre-set token (for scripts/CI)
ZENODO_TOKEN="your_token" zenodo-dl 1234567
```

### Finding your Record ID

The record ID is the number in the Zenodo URL:

```
https://zenodo.org/records/1234567
                        └──────┘
                        Record ID

https://zenodo.org/uploads/1234567  (drafts)
```

## Token Setup

For restricted or draft records, you need a Personal Access Token:

1. Log in to [Zenodo](https://zenodo.org/login)
2. Go to [Applications settings](https://zenodo.org/account/settings/applications/)
3. Click **+ New token**
4. Name it (e.g., "zenodo-dl")
5. Check **`deposit:read`** scope
6. Click **Create** and copy the token immediately

### Token Storage Options

The script checks for tokens in this order:

| Method | Command | Use case |
|--------|---------|----------|
| Environment variable | `export ZENODO_TOKEN="..."` | CI/scripts, one-time use |
| Dotfile | `~/.zenodo_token` | Repeated local use |
| Interactive prompt | (automatic) | One-time downloads |

**Secure dotfile setup:**

```bash
echo "your_token" > ~/.zenodo_token
chmod 600 ~/.zenodo_token
```

**With GPG encryption:**

```bash
# Store
echo "your_token" | gpg -c -o ~/.zenodo_token.gpg

# Use
export ZENODO_TOKEN=$(gpg -d ~/.zenodo_token.gpg 2>/dev/null)
zenodo-dl 1234567
```

## Menu Options

```
0) Help — token setup instructions
1) List files
2) Download all (ZIP or individual)
3) Download specific file(s)
4) Extract archive

t) Remove stored token
r) Change record ID
q) Quit
```

## Examples

**Download all files as ZIP:**

```bash
$ zenodo-dl 1234567
# Select option 2 → 1 (ZIP) → specify output directory
```

**Download specific files by pattern:**

```bash
$ zenodo-dl 1234567
# Select option 3 → enter pattern like "MMLU" or ".csv"
```

**Non-interactive (for scripts):**

```bash
# List files
curl -s -H "Authorization: Bearer $ZENODO_TOKEN" \
  "https://zenodo.org/api/records/1234567" | jq -r '.files[].key'

# Download ZIP
curl -L -H "Authorization: Bearer $ZENODO_TOKEN" \
  "https://zenodo.org/api/records/1234567/files-archive" \
  -o data.zip
```

## Troubleshooting

**"Token validation failed (HTTP 401)"**
- Token doesn't have `deposit:read` scope
- Token expired or revoked

**"Token validation failed (HTTP 404)"**
- Record ID is incorrect
- Record is not accessible with your account

**ZIP download returns error message instead of file**
- Record might be a draft — the API endpoint differs
- Try downloading individual files instead (option 2 → 2)

## License

Apache 2.0

## Contributing

Issues and PRs welcome.
