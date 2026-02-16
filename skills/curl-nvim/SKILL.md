---
name: curl-nvim
description: Use when authoring or debugging curl.nvim `.curl` workflows, especially to resolve `---` variables / `---source` env files, export the exact curl command under cursor, or execute the request from terminal/headless Codex.
---

# curl.nvim Workflow

## Overview

This skill gives Codex a deterministic way to work with `.curl` files using the same parser/resolution logic as `curl.nvim`. Use it when the user wants export/execute behavior that matches the plugin.

## Use This Skill For

- `.curl` files that include `--- var=value` directives.
- `.curl` files that use `---source=...` env files.
- `.curl` files organized with markdown-style headers (`##`, `###`, `####`) as meaningful blocks.
- under-cursor export of the fully resolved curl command.
- executing a request from `.curl` in terminal/headless mode.
- verbose/debug output where stderr should be visible.

## Preferred Workflow

1. Identify target file and cursor line.
2. Export first to verify resolution:
   - `skills/curl-nvim/scripts/exec_from_curl_file.sh --file path/to/file.curl --line 12 --mode export`
3. Execute when requested:
   - `skills/curl-nvim/scripts/exec_from_curl_file.sh --file path/to/file.curl --line 12 --mode exec`
4. For verbose/debug traces:
   - add `--show-stderr`

## Request Style Conventions

Prefer URL-first request layout in `.curl` files:

```bash
curl $concrete_service/healthz -H "Accept: application/json"
```

Prefer composing a full service base variable, not host/port interpolation at call site:

```bash
--- concrete_service=http://127.0.0.1:9200
curl $concrete_service/healthz
```

Avoid this style in requests:

```bash
curl http://$host:$concrete_service_port/healthz
```

Reason: URL-first + service-base variables are easier to read, search, and reuse across commands.

## JSON Body Style

In `.curl` files, prefer multiline JSON body style after `-d`:

```bash
curl $crematorium/admin/sync/day -H "Content-Type: application/json" -u admin:admin -d
{
  "day": "$day"
}
```

Avoid escaped shell one-liners in `.curl` files:

```bash
curl ... -d "{\"day\":\"$day\"}"
```

Use the multiline body style so `curl.nvim` can apply its normal formatting/quoting behavior consistently.

## How Curl Is Called

For command-under-cursor parsing, `curl.nvim` appends `-sSL` automatically.

Skill helper behavior (`exec_from_curl_file.sh`):

- `--mode export`: prints resolved command (includes `-sSL`).
- `--mode exec`: runs command via shell (`bash -c`, fallback `sh -c`, then `zsh`/`fish`), using the parsed command string.
- `--show-stderr`: prepends stderr output to stdout on successful requests (useful for `-v` traces).
- `--curl-binary`: replaces leading `curl` token.

Notes:

- Add `-v` directly in the `.curl` request when you need verbose traces.
- In skill helper runs (`nvim -u NONE`), no user Neovim config is loaded, so plugin `default_flags` config is not applied unless those flags are written directly in the request.

## Path Resolution Rules

Mirror plugin behavior:

- `--- var = value` and `---var=value` are both valid.
- Prefer `--- var=value` style in examples and edits, so variable names stay easy to target with word search (`*`) and motions.
- Comment convention for header-fold workflows:
  - use `##` / `###` / `####` for section headers
  - use `#####` for regular comments/notes
  - when needed, pair this with fold pattern `^%s*#{1,4}%s+` so `#####` stays a normal comment
- `---source=...` supports:
  - absolute paths
  - `~/...`
  - `$HOME/...` and `${HOME}/...`
  - relative paths
- Relative `---source` resolution:
  - default: directory of the `.curl` file
  - override with `--root-anchor` to emulate plugin-managed scoped buffers (open-time cwd)

Tool prerequisites and resolution:

- `nvim` must be installed and available in `PATH`.
- `curl.nvim` plugin dir is resolved strictly:
  - first: `--plugin-dir <dir>`
  - fallback: `CURL_NVIM_PLUGIN_DIR`
  - otherwise: fail with explicit error
- No plugin auto-discovery and no auto-install.

## Script Interface

Primary entrypoint:

- `skills/curl-nvim/scripts/exec_from_curl_file.sh`

Options:

- `--file <path>`: required
- `--line <n>`: cursor line (default `1`)
- `--mode export|exec`: default `exec`
- `--show-stderr`: include stderr before stdout on successful execution
- `--print-command`: print resolved command to stderr before running
- `--root-anchor <dir>`: base dir for relative `---source`
- `--plugin-dir <dir>`: explicit `curl.nvim` plugin directory (required unless `CURL_NVIM_PLUGIN_DIR` is set)
- `--curl-binary <name-or-path>`: replace leading `curl` alias

## Agent Rules

- For mutating requests (`POST`, `PUT`, `PATCH`, `DELETE`), export first unless the user explicitly asks to execute immediately.
- If command resolution fails due to missing `---source` file, stop and report the exact path.
- If user asks why verbose output is missing, run with `--show-stderr`.
