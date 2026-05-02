# openbox

Public server scripts for quick service setup and reverse proxy management.

## Scripts

- `openbox.sh`: interactive Caddy manager with one-click reverse proxy setup.

## Usage

```bash
bash openbox.sh
```

For convenience:

```bash
alias cm='bash /path/to/openbox.sh'
```

## Notes

- Run as `root`.
- The reverse proxy helper can install Caddy, detect local listening ports, preview Caddyfile changes, validate config, reload Caddy, and roll back on failure.
- Do not commit private keys, API keys, OAuth tokens, or production config files.
