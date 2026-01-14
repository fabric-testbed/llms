# Using FABRIC AI Models with ChatBox and Claude Code

> Quick setup guide for connecting to LLM models hosted on FABRIC DGX Spark

---

## Connection Options

| Method | Endpoint | Use Case |
|--------|----------|----------|
| **Public HTTPS** | `https://ai.fabric-testbed.net` | Remote access, no tunnel needed |
| **SSH Tunnel** | `http://localhost:4000` | Internal/development access |

---

## Option A: Public HTTPS Endpoint (Recommended)

No SSH tunnel required. Use this for easy remote access.

### Configure ChatBox (Public Endpoint)

1. Open **ChatBox** → **Settings** → **Model Provider**
2. Click **Add**
3. Fill in:
   - **Name**: `FABRIC AI`
   - **API Key**: `<your provided key>`
   - **API Host**: `https://ai.fabric-testbed.net/`
4. Under **Model**, click **New**:
   - **Model ID**: `gpt-oss-20b`
   - **Context Window**: `131072`
   - **Max Output Tokens**: `131072`
5. Click **Test Model** → **Save**

### Configure Claude Code (Public Endpoint)

```bash
export ANTHROPIC_BASE_URL=https://ai.fabric-testbed.net/
export ANTHROPIC_AUTH_TOKEN=<your provided key>
export ANTHROPIC_DEFAULT_SONNET_MODEL=claude-3-5-sonnet-20241022

claude
```

---

## Option B: SSH Tunnel (Internal Access)

Use this if you need direct access to the internal network.

### Step 1: Create SSH Tunnel

```bash
ssh -F ~/.ssh/fabric-config -L 4000:10.20.5.251:4000 -L 2222:10.20.5.251:22 152.54.15.35
```

Keep this terminal open while using the models.

### Configure ChatBox (SSH Tunnel)

1. Open **ChatBox** → **Settings** → **Model Provider**
2. Click **Add**
3. Fill in:
   - **Name**: `DGX Spark RENCI`
   - **API Key**: `<your provided key>`
   - **API Host**: `http://localhost:4000/`
4. Under **Model**, click **New**:
   - **Model ID**: `qwen3-coder-30b`
   - **Context Window**: `262144`
   - **Max Output Tokens**: `262144`
5. Click **Test Model** → **Save**

---

### Configure Claude Code (SSH Tunnel)

```bash
export ANTHROPIC_BASE_URL=http://localhost:4000/
export ANTHROPIC_AUTH_TOKEN=<your provided key>
export ANTHROPIC_DEFAULT_SONNET_MODEL=claude-3-5-sonnet-20241022

claude
```

---

## Persistent Configuration

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# FABRIC AI Model Configuration
# Option A: Public endpoint (recommended)
export ANTHROPIC_BASE_URL=https://ai.fabric-testbed.net/
# Option B: SSH tunnel (uncomment if using tunnel)
# export ANTHROPIC_BASE_URL=http://localhost:4000/

export ANTHROPIC_AUTH_TOKEN=<your provided key>
export ANTHROPIC_DEFAULT_SONNET_MODEL=claude-3-5-sonnet-20241022
```

---

## Available Models

| Model ID | Best For                                |
|----------|-----------------------------------------|
| `qwen3-coder-30b` | Code generation, fast responses         |
| `claude-3-5-sonnet-20241022` | General purpose (routed to local model) |
| `gpt-oss-20b` | Basic reasoning tasks                   |

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Connection refused | Ensure SSH tunnel is active |
| 401 Unauthorized | Check API key is correct |
| Timeout | Model may be loading; wait 2-3 minutes |
| Model not found | Verify model ID matches exactly |

---

## Notes

- **Public endpoint**: No tunnel required; works from anywhere with internet access
- **SSH tunnel**: Must remain active for the duration of your session
- Models are hosted on NVIDIA DGX Spark with 128GB unified memory
- Response times depend on model size and current load
- Contact FABRIC support for API key requests
