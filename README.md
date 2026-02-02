# zenodo_dl

Download files from Zenodo repositories (public or your restricted/draft).

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
2. `~/.zenodo_token` file
3. Interactive prompt

## Requirements

- `curl`
- `jq`

```bash
# Debian/Ubuntu
sudo apt install curl jq

# macOS
brew install curl jq
```

## Cleanup

```bash
./zenodo_dl.sh --uninstall  # removes ~/.zenodo_token
rm zenodo_dl.sh             # delete the script
```

## License

Apache 2.0