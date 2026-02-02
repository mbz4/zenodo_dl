# zenodo_dl

Download files from Zenodo repositories (public, restricted, or draft).

## Quick Start

**Run directly (no install):**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mbz4/zenodo_dl/main/zenodo_dl.sh)
```

**Or download and run:**

```bash
curl -LO https://raw.githubusercontent.com/mbz4/zenodo_dl/main/zenodo_dl.sh
chmod +x zenodo_dl.sh
./zenodo_dl.sh
```

## Usage

```bash
./zenodo_dl.sh              # interactive — prompts for record ID
./zenodo_dl.sh 12345678     # with record ID
./zenodo_dl.sh --help       # help
./zenodo_dl.sh --uninstall  # remove stored token
```

With pre-set token (CI/scripts):

```bash
ZENODO_TOKEN="your_token" ./zenodo_dl.sh 12345678 # Zenodo record ID
```

## Token

For restricted or draft records, you need a Personal Access Token:

1. https://zenodo.org/account/settings/applications/
2. **+ New token** → name it → check **deposit:read** → Create
3. Copy immediately (shown only once)

The script looks for tokens in order:
1. `$ZENODO_TOKEN` environment variable
2. `~/.zenodo_token.enc` (encrypted, passphrase required)
3. `~/.zenodo_token` (plaintext, chmod 600)
4. Interactive prompt

### Encrypted storage (default)

When saving a token, you'll be prompted to choose:

```
Save token?
  1) Encrypted (passphrase each use) ← recommended
  2) Plaintext (chmod 600)
  3) Don't save
```

Encrypted tokens use AES-256-CBC with PBKDF2 key derivation via openssl.

## Requirements

- `curl`
- `jq`
- `openssl` (for token encryption)

```bash
# Debian/Ubuntu
sudo apt install curl jq openssl

# macOS (usually pre-installed)
brew install curl jq openssl
```

## Cleanup

```bash
./zenodo_dl.sh --uninstall  # removes ~/.zenodo_token and ~/.zenodo_token.enc
rm zenodo_dl.sh             # delete the script
```

## License

Apache 2.0