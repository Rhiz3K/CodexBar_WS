# CodexBar Server

A Linux-compatible web server that provides a real-time dashboard for monitoring AI provider usage limits. Built with Swift and Hummingbird framework.

## Features

- **Real-time Dashboard**: Web UI showing usage for all configured providers
- **Usage History**: SQLite-based storage with historical data and charts
- **Cost Tracking**: Token and cost history for Claude and Codex
- **Predictions**: Estimates when you'll hit rate limits based on usage patterns
- **REST API**: JSON endpoints for integration with other tools
- **Cross-platform**: Works on Linux and macOS

## Quick Start

### Install (recommended)

```bash
brew tap steipete/tap
brew install steipete/tap/codexbar
```

### Run

```bash
# Start server (foreground)
codexbar server run -v

# With custom port
codexbar server run --port 9000
```

### Autostart (systemd user service)

```bash
# Install + enable + start the service (starts after login)
codexbar server install --port 9000 --interval 300 -v

# Inspect
systemctl --user status codexbar-server
journalctl --user -u codexbar-server -f

# Uninstall
codexbar server uninstall
```

### Build from source (advanced)

```bash
# Set Swift path (Linux)
export PATH=/opt/swift/usr/bin:$PATH

# Build server
swift build --product CodexBarServer

# Build CLI (required for data fetching)
swift build --product CodexBarCLI

# Run
./.build/debug/CodexBarServer -v
```

### Access

- Dashboard: http://127.0.0.1:8080/
- Health check: http://127.0.0.1:8080/health

## Configuration

### Environment Variables

The server primarily uses CLI flags. These environment variables are supported as defaults (CLI flags still override them):

| Variable | Default | Description |
|----------|---------|-------------|
| `CODEXBAR_PORT` | `8080` | Server port |
| `CODEXBAR_HOST` | `127.0.0.1` | Bind address |
| `CODEXBAR_DB_PATH` | `~/.codexbar/usage_history.sqlite` | Database path |
| `CODEXBAR_INTERVAL` | `300` | Fetch interval (seconds) |

### Provider Setup

The server uses CodexBarCLI to fetch data. Configure providers as you would for the CLI:

| Provider | Linux Source | Requirements |
|----------|--------------|--------------|
| Codex | `codex-cli` | Codex CLI installed and configured |
| Claude | `oauth` | Claude CLI OAuth token (`~/.claude/.credentials.json`) |
| Gemini | `api` | Gemini CLI OAuth (`~/.gemini/oauth_creds.json`) |

## API Endpoints

### Dashboard

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | HTML dashboard |
| `/provider/{name}` | GET | Provider detail page |

### Status & Data

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/status` | GET | All providers with predictions and cost |
| `/api/providers` | GET | List of active providers |
| `/api/history/{provider}` | GET | Usage history (query: `hours`, `limit`) |
| `/api/prediction/{provider}` | GET | Prediction details |
| `/api/stats/{provider}` | GET | Usage statistics |

### Cost Data

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/cost` | GET | Current cost for all providers |
| `/api/cost/{provider}` | GET | Current cost for provider |
| `/api/cost/history` | GET | Cost history (query: `hours`, `limit`) |
| `/api/cost/history/{provider}` | GET | Provider cost history |

### Control

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/fetch` | POST | Trigger immediate data fetch |
| `/health` | GET | Health check with record counts + scheduler warnings |

## API Examples

```bash
# Get all providers status
curl http://127.0.0.1:8080/api/status | jq

# Get Claude usage history (last 24 hours)
curl "http://127.0.0.1:8080/api/history/claude?hours=24&limit=100"

# Get cost history (last 7 days)
curl "http://127.0.0.1:8080/api/cost/history?hours=168"

# Trigger manual fetch
curl -X POST http://127.0.0.1:8080/api/fetch

# Health check
curl http://127.0.0.1:8080/health
# {"status":"ok","records":114,"costRecords":4,"warnings":[]}
# If the scheduler hits provider errors (e.g. expired OAuth token), status will be "warning" and warnings will contain details.
```

## Database Schema

The server stores data in SQLite (`~/.codexbar/usage_history.sqlite`):

### usage_history table
Stores usage snapshots with primary/secondary/tertiary usage percentages, reset times, account info.

### cost_history table
Stores token counts and cost data:
- `session_tokens`, `session_cost_usd` - Today's usage
- `period_tokens`, `period_cost_usd` - 30-day totals
- `models_used` - JSON array of model names

## Dashboard Features

### Usage Cards
Each provider shows:
- **Session usage** (5-hour window) - dashed line
- **Weekly usage** - solid colored line
- **Reset countdown**
- **Prediction status** (healthy/warning/critical)
- **Token/cost stats** (Claude, Codex only)
- **Models used**

### Color Coding
Usage percentage determines line color:
- 0-25%: Blue
- 25-50%: Green
- 50-75%: Yellow
- 75-90%: Orange
- 90%+: Red

### Prediction Status
- **Healthy**: >4 hours to limit
- **Warning**: 1-4 hours to limit
- **Critical**: <1 hour to limit (or limit before reset)
- **Decreasing**: Usage going down

## Cost Tracking

### Supported Providers

| Provider | Tokens | Cost | Source |
|----------|--------|------|--------|
| Claude | Yes | Yes | Local JSONL logs |
| Codex | Yes | Yes | Local JSONL logs |
| Gemini | No | No | API only returns % |

### Cost Fetch Timing
- Claude: ~48 seconds (scans JSONL logs)
- Codex: ~6 seconds
- Timeout: 120 seconds per provider

## Systemd Service (Linux)

Create `/etc/systemd/system/codexbar-server.service`:

```ini
[Unit]
Description=CodexBar Server
After=network.target

[Service]
Type=simple
User=your-username
WorkingDirectory=/path/to/CodexBar_WS
Environment="PATH=/opt/swift/usr/bin:/usr/bin"
ExecStart=/path/to/CodexBar_WS/.build/release/CodexBarServer
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable codexbar-server
sudo systemctl start codexbar-server
sudo systemctl status codexbar-server
```

## Development

### Project Structure

```
Sources/CodexBarServer/
  ServerMain.swift      # Entry point, AppState, CLI parsing
  Routes.swift          # HTTP route handlers
  HTMLTemplates.swift   # Dashboard HTML/CSS/JS generation
  UsageScheduler.swift  # Periodic data fetching

Sources/CodexBarCore/Storage/
  UsageHistoryStore.swift   # SQLite operations
  UsagePrediction.swift     # Prediction engine

TestsLinux/
  UsageHistoryStoreTests.swift
  UsagePredictionTests.swift
```

### Running Tests

```bash
# All Linux tests
swift test --filter CodexBarLinuxTests

# Specific test suite
swift test --filter UsageHistoryStoreTests
swift test --filter UsagePredictionTests
```

### Building for Release

```bash
swift build -c release --product CodexBarServer
```

## Troubleshooting

### Server won't start
- Check if port 8080 is in use: `lsof -i :8080`
- Verify Swift is in PATH: `which swift`
- Check CodexBarCLI is built: `ls .build/debug/CodexBarCLI`

### No data appearing
- Check server logs: `tail -f /tmp/codexbar-server.log`
- Verify CLI works: `./.build/debug/CodexBarCLI --provider codex --source cli`
- Check OAuth tokens exist for Claude/Gemini

### Cost data missing
- Only Claude and Codex support cost tracking
- Claude cost fetch takes ~48 seconds
- Check for JSONL logs in `~/.claude/` or `~/.codex/`

### Database errors
- Check permissions: `ls -la ~/.codexbar/`
- Try deleting and recreating: `rm ~/.codexbar/usage_history.sqlite`
