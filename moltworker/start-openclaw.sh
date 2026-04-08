#!/bin/bash
# Startup script for OpenClaw in Cloudflare Sandbox
# This script:
# 1. Restores config/workspace/skills from R2 via rclone (if configured)
# 2. Runs openclaw onboard --non-interactive to configure from env vars
# 3. Patches config for features onboard doesn't cover (channels, gateway auth)
# 4. Starts a background sync loop (rclone, watches for file changes)
# 5. Starts the gateway

set -e

if pgrep -f "openclaw gateway" > /dev/null 2>&1; then
    echo "OpenClaw gateway is already running, exiting."
    exit 0
fi

CONFIG_DIR="/root/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
WORKSPACE_DIR="/root/clawd"
SKILLS_DIR="/root/clawd/skills"
RCLONE_CONF="/root/.config/rclone/rclone.conf"
LAST_SYNC_FILE="/tmp/.last-sync"

echo "Config directory: $CONFIG_DIR"

mkdir -p "$CONFIG_DIR"

# ============================================================
# RCLONE SETUP
# ============================================================

r2_configured() {
    [ -n "$R2_ACCESS_KEY_ID" ] && [ -n "$R2_SECRET_ACCESS_KEY" ] && [ -n "$CF_ACCOUNT_ID" ]
}

R2_BUCKET="${R2_BUCKET_NAME:-moltbot-data}"

setup_rclone() {
    mkdir -p "$(dirname "$RCLONE_CONF")"
    cat > "$RCLONE_CONF" << EOF
[r2]
type = s3
provider = Cloudflare
access_key_id = $R2_ACCESS_KEY_ID
secret_access_key = $R2_SECRET_ACCESS_KEY
endpoint = https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com
acl = private
no_check_bucket = true
EOF
    touch /tmp/.rclone-configured
    echo "Rclone configured for bucket: $R2_BUCKET"
}

RCLONE_FLAGS="--transfers=16 --fast-list --s3-no-check-bucket"

# ============================================================
# RESTORE FROM R2
# ============================================================

if r2_configured; then
    setup_rclone

    echo "Checking R2 for existing backup..."
    # Check if R2 has an openclaw config backup
    if rclone ls "r2:${R2_BUCKET}/openclaw/openclaw.json" $RCLONE_FLAGS 2>/dev/null | grep -q openclaw.json; then
        echo "Restoring config from R2..."
        rclone copy "r2:${R2_BUCKET}/openclaw/" "$CONFIG_DIR/" $RCLONE_FLAGS -v 2>&1 || echo "WARNING: config restore failed with exit code $?"
        echo "Config restored"
    elif rclone ls "r2:${R2_BUCKET}/clawdbot/clawdbot.json" $RCLONE_FLAGS 2>/dev/null | grep -q clawdbot.json; then
        echo "Restoring from legacy R2 backup..."
        rclone copy "r2:${R2_BUCKET}/clawdbot/" "$CONFIG_DIR/" $RCLONE_FLAGS -v 2>&1 || echo "WARNING: legacy config restore failed with exit code $?"
        if [ -f "$CONFIG_DIR/clawdbot.json" ] && [ ! -f "$CONFIG_FILE" ]; then
            mv "$CONFIG_DIR/clawdbot.json" "$CONFIG_FILE"
        fi
        echo "Legacy config restored and migrated"
    else
        echo "No backup found in R2, starting fresh"
    fi

    # Restore workspace
    REMOTE_WS_COUNT=$(rclone ls "r2:${R2_BUCKET}/workspace/" $RCLONE_FLAGS 2>/dev/null | wc -l)
    if [ "$REMOTE_WS_COUNT" -gt 0 ]; then
        echo "Restoring workspace from R2 ($REMOTE_WS_COUNT files)..."
        mkdir -p "$WORKSPACE_DIR"
        rclone copy "r2:${R2_BUCKET}/workspace/" "$WORKSPACE_DIR/" $RCLONE_FLAGS -v 2>&1 || echo "WARNING: workspace restore failed with exit code $?"
        echo "Workspace restored"
    fi

    # Restore skills
    REMOTE_SK_COUNT=$(rclone ls "r2:${R2_BUCKET}/skills/" $RCLONE_FLAGS 2>/dev/null | wc -l)
    if [ "$REMOTE_SK_COUNT" -gt 0 ]; then
        echo "Restoring skills from R2 ($REMOTE_SK_COUNT files)..."
        mkdir -p "$SKILLS_DIR"
        rclone copy "r2:${R2_BUCKET}/skills/" "$SKILLS_DIR/" $RCLONE_FLAGS -v 2>&1 || echo "WARNING: skills restore failed with exit code $?"
        echo "Skills restored"
    fi

    # Restore .config (gcloud, gws, chrome profile, etc.)
    # Exclude rclone/ to avoid overwriting the rclone.conf we just wrote above
    REMOTE_DC_COUNT=$(rclone ls "r2:${R2_BUCKET}/dot-config/" $RCLONE_FLAGS 2>/dev/null | wc -l)
    if [ "$REMOTE_DC_COUNT" -gt 0 ]; then
        echo "Restoring .config from R2 ($REMOTE_DC_COUNT files)..."
        mkdir -p /root/.config
        rclone copy "r2:${R2_BUCKET}/dot-config/" "/root/.config/" $RCLONE_FLAGS \
            --exclude='rclone/**' -v 2>&1 || echo "WARNING: .config restore failed with exit code $?"
        echo ".config restored"
    fi
else
    echo "R2 not configured, starting fresh"
fi

# ============================================================
# ONBOARD (only if no config exists yet)
# ============================================================
if [ ! -f "$CONFIG_FILE" ]; then
    echo "No existing config found, running openclaw onboard..."

    AUTH_ARGS=""
    if [ -n "$ANTHROPIC_API_KEY" ]; then
        AUTH_ARGS="--auth-choice apiKey --anthropic-api-key $ANTHROPIC_API_KEY"
    elif [ -n "$CLOUDFLARE_AI_GATEWAY_API_KEY" ] && [ -n "$CF_AI_GATEWAY_ACCOUNT_ID" ] && [ -n "$CF_AI_GATEWAY_GATEWAY_ID" ]; then
        AUTH_ARGS="--auth-choice cloudflare-ai-gateway-api-key \
            --cloudflare-ai-gateway-account-id $CF_AI_GATEWAY_ACCOUNT_ID \
            --cloudflare-ai-gateway-gateway-id $CF_AI_GATEWAY_GATEWAY_ID \
            --cloudflare-ai-gateway-api-key $CLOUDFLARE_AI_GATEWAY_API_KEY"
    elif [ -n "$OPENAI_API_KEY" ]; then
        AUTH_ARGS="--auth-choice openai-api-key --openai-api-key $OPENAI_API_KEY"
    fi

    openclaw onboard --non-interactive --accept-risk \
        --mode local \
        $AUTH_ARGS \
        --gateway-port 18789 \
        --gateway-bind lan \
        --skip-channels \
        --skip-skills \
        --skip-health

    echo "Onboard completed"
else
    echo "Using existing config"
fi

# ============================================================
# PATCH CONFIG (channels, gateway auth, trusted proxies)
# ============================================================
# openclaw onboard handles provider/model config, but we need to patch in:
# - Channel config (Telegram, Discord, Slack)
# - Gateway token auth
# - Trusted proxies for sandbox networking
# - Base URL override for legacy AI Gateway path
node << 'EOFPATCH'
const fs = require('fs');

const configPath = '/root/.openclaw/openclaw.json';
console.log('Patching config at:', configPath);
let config = {};

try {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch (e) {
    console.log('Starting with empty config');
}

config.gateway = config.gateway || {};
config.channels = config.channels || {};

// Gateway configuration
config.gateway.port = 18789;
config.gateway.mode = 'local';
config.gateway.trustedProxies = ['10.1.0.0'];

if (process.env.OPENCLAW_GATEWAY_TOKEN) {
    config.gateway.auth = config.gateway.auth || {};
    config.gateway.auth.token = process.env.OPENCLAW_GATEWAY_TOKEN;
}

config.gateway.controlUi = config.gateway.controlUi || {};
config.gateway.controlUi.allowInsecureAuth = true;
if (process.env.WORKER_URL) {
    const origins = config.gateway.controlUi.allowedOrigins || [];
    if (!origins.includes(process.env.WORKER_URL)) {
        origins.push(process.env.WORKER_URL);
    }
    config.gateway.controlUi.allowedOrigins = origins;
}

// Legacy AI Gateway base URL override:
// ANTHROPIC_BASE_URL is picked up natively by the Anthropic SDK,
// so we don't need to patch the provider config. Writing a provider
// entry without a models array breaks OpenClaw's config validation.

// AI Gateway model override (CF_AI_GATEWAY_MODEL=provider/model-id)
// Adds a provider entry for any AI Gateway provider and sets it as default model.
// Examples:
//   workers-ai/@cf/google/gemma-4-26b-a4b-it
//   openai/gpt-4o
//   anthropic/claude-sonnet-4-5
if (process.env.CF_AI_GATEWAY_MODEL) {
    const raw = process.env.CF_AI_GATEWAY_MODEL;
    const slashIdx = raw.indexOf('/');
    const gwProvider = raw.substring(0, slashIdx);
    const modelId = raw.substring(slashIdx + 1);

    const accountId = process.env.CF_AI_GATEWAY_ACCOUNT_ID;
    const gatewayId = process.env.CF_AI_GATEWAY_GATEWAY_ID;
    const apiKey = process.env.CLOUDFLARE_AI_GATEWAY_API_KEY;

    let baseUrl;
    if (accountId && gatewayId) {
        baseUrl = 'https://gateway.ai.cloudflare.com/v1/' + accountId + '/' + gatewayId + '/' + gwProvider;
        if (gwProvider === 'workers-ai') baseUrl += '/v1';
    } else if (gwProvider === 'workers-ai' && process.env.CF_ACCOUNT_ID) {
        baseUrl = 'https://api.cloudflare.com/client/v4/accounts/' + process.env.CF_ACCOUNT_ID + '/ai/v1';
    }

    if (baseUrl && apiKey) {
        const api = gwProvider === 'anthropic' ? 'anthropic-messages' : 'openai-completions';
        const providerName = 'cf-ai-gw-' + gwProvider;

        config.models = config.models || {};
        config.models.providers = config.models.providers || {};
        config.models.providers[providerName] = {
            baseUrl: baseUrl,
            apiKey: apiKey,
            api: api,
            models: [{ id: modelId, name: modelId, contextWindow: 131072, maxTokens: 8192, input: ['text', 'image'] }],
        };
        config.agents = config.agents || {};
        config.agents.defaults = config.agents.defaults || {};
        config.agents.defaults.model = { primary: providerName + '/' + modelId };
        config.agents.defaults.imageModel = { primary: providerName + '/' + modelId };
        console.log('AI Gateway model override: provider=' + providerName + ' model=' + modelId + ' via ' + baseUrl);
    } else {
        console.warn('CF_AI_GATEWAY_MODEL set but missing required config (account ID, gateway ID, or API key)');
    }
}

// Telegram configuration
// Overwrite entire channel object to drop stale keys from old R2 backups
// that would fail OpenClaw's strict config validation (see #47)
if (process.env.TELEGRAM_BOT_TOKEN) {
    const dmPolicy = process.env.TELEGRAM_DM_POLICY || 'pairing';
    config.channels.telegram = {
        botToken: process.env.TELEGRAM_BOT_TOKEN,
        enabled: true,
        dmPolicy: dmPolicy,
    };
    if (process.env.TELEGRAM_DM_ALLOW_FROM) {
        config.channels.telegram.allowFrom = process.env.TELEGRAM_DM_ALLOW_FROM.split(',');
    } else if (dmPolicy === 'open') {
        config.channels.telegram.allowFrom = ['*'];
    }
}

// Discord configuration
// Discord uses a nested dm object: dm.policy, dm.allowFrom (per DiscordDmConfig)
if (process.env.DISCORD_BOT_TOKEN) {
    const dmPolicy = process.env.DISCORD_DM_POLICY || 'pairing';
    const dm = { policy: dmPolicy };
    if (dmPolicy === 'open') {
        dm.allowFrom = ['*'];
    }
    config.channels.discord = {
        token: process.env.DISCORD_BOT_TOKEN,
        enabled: true,
        dm: dm,
    };
}

// Slack configuration
if (process.env.SLACK_BOT_TOKEN && process.env.SLACK_APP_TOKEN) {
    config.channels.slack = {
        botToken: process.env.SLACK_BOT_TOKEN,
        appToken: process.env.SLACK_APP_TOKEN,
        enabled: true,
    };
}

fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
console.log('Configuration patched successfully');
EOFPATCH

# ============================================================
# BACKGROUND SYNC LOOP
# ============================================================
# Uses find + --files-from for lightweight 30s incremental syncs.
# Every hour (120 cycles), runs a full rclone sync to clean up
# deleted/renamed files from R2.
if r2_configured; then
    echo "Starting background R2 sync loop..."
    (
        MARKER=/tmp/.last-sync-marker
        LOGFILE=/tmp/r2-sync.log
        DOTCONFIG_DIR="/root/.config"
        CYCLE=0
        touch "$MARKER"

        while true; do
            sleep 30
            CYCLE=$((CYCLE + 1))

            if [ $((CYCLE % 120)) -eq 0 ]; then
                # ── HOURLY: full rclone sync (cleans up deleted files from R2) ──
                echo "[sync] Full sync at $(date)" >> "$LOGFILE"
                rclone sync "$CONFIG_DIR/" "r2:${R2_BUCKET}/openclaw/" \
                    $RCLONE_FLAGS --exclude='*.lock' --exclude='*.log' --exclude='*.tmp' 2>> "$LOGFILE"
                rclone sync "$WORKSPACE_DIR/" "r2:${R2_BUCKET}/workspace/" \
                    $RCLONE_FLAGS --exclude='skills/**' --exclude='.git/**' --exclude='node_modules/**' \
                    --exclude='.agent-browser/**' --exclude='google-cloud-sdk/**' 2>> "$LOGFILE"
                rclone sync "$SKILLS_DIR/" "r2:${R2_BUCKET}/skills/" \
                    $RCLONE_FLAGS 2>> "$LOGFILE"
                rclone sync "$DOTCONFIG_DIR/" "r2:${R2_BUCKET}/dot-config/" \
                    $RCLONE_FLAGS \
                    --exclude='rclone/**' \
                    --exclude='chromium/**/Cache/**' \
                    --exclude='chromium/**/Code Cache/**' \
                    --exclude='chromium/**/GPUCache/**' \
                    --exclude='chromium/**/Service Worker/CacheStorage/**' \
                    --exclude='google-chrome/**/Cache/**' \
                    --exclude='google-chrome/**/Code Cache/**' \
                    --exclude='google-chrome/**/GPUCache/**' 2>> "$LOGFILE"
                touch "$MARKER"
                echo "[sync] Full sync complete at $(date)" >> "$LOGFILE"
            else
                # ── INCREMENTAL: find changed files + rclone copy --files-from ──
                CHANGED_CONFIG=/tmp/.changed-config
                CHANGED_WORKSPACE=/tmp/.changed-workspace
                CHANGED_SKILLS=/tmp/.changed-skills
                CHANGED_DOTCONFIG=/tmp/.changed-dotconfig

                find "$CONFIG_DIR" -newer "$MARKER" -type f \
                    -not -name '*.lock' -not -name '*.log' -not -name '*.tmp' \
                    -printf '%P\n' 2>/dev/null > "$CHANGED_CONFIG"
                find "$WORKSPACE_DIR" -newer "$MARKER" -type f \
                    -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/skills/*' \
                    -not -path '*/.agent-browser/*' -not -path '*/google-cloud-sdk/*' \
                    -printf '%P\n' 2>/dev/null > "$CHANGED_WORKSPACE"
                find "$SKILLS_DIR" -newer "$MARKER" -type f \
                    -printf '%P\n' 2>/dev/null > "$CHANGED_SKILLS"
                find "$DOTCONFIG_DIR" -newer "$MARKER" -type f \
                    -not -path '*/rclone/*' \
                    -not -path '*/Cache/*' -not -path '*/Code Cache/*' \
                    -not -path '*/GPUCache/*' -not -path '*/Service Worker/CacheStorage/*' \
                    -printf '%P\n' 2>/dev/null > "$CHANGED_DOTCONFIG"

                TOTAL=$(cat "$CHANGED_CONFIG" "$CHANGED_WORKSPACE" "$CHANGED_SKILLS" "$CHANGED_DOTCONFIG" 2>/dev/null | wc -l)

                if [ "$TOTAL" -gt 0 ]; then
                    echo "[sync] Incremental upload ($TOTAL files) at $(date)" >> "$LOGFILE"
                    [ -s "$CHANGED_CONFIG" ] && rclone copy "$CONFIG_DIR/" "r2:${R2_BUCKET}/openclaw/" \
                        --files-from="$CHANGED_CONFIG" $RCLONE_FLAGS 2>> "$LOGFILE"
                    [ -s "$CHANGED_WORKSPACE" ] && rclone copy "$WORKSPACE_DIR/" "r2:${R2_BUCKET}/workspace/" \
                        --files-from="$CHANGED_WORKSPACE" $RCLONE_FLAGS 2>> "$LOGFILE"
                    [ -s "$CHANGED_SKILLS" ] && rclone copy "$SKILLS_DIR/" "r2:${R2_BUCKET}/skills/" \
                        --files-from="$CHANGED_SKILLS" $RCLONE_FLAGS 2>> "$LOGFILE"
                    [ -s "$CHANGED_DOTCONFIG" ] && rclone copy "$DOTCONFIG_DIR/" "r2:${R2_BUCKET}/dot-config/" \
                        --files-from="$CHANGED_DOTCONFIG" $RCLONE_FLAGS 2>> "$LOGFILE"
                    echo "[sync] Incremental complete at $(date)" >> "$LOGFILE"
                fi
                touch "$MARKER"
                date -Iseconds > "$LAST_SYNC_FILE"
            fi
        done
    ) &
    echo "Background sync loop started (PID: $!)"
fi

# ============================================================
# LINK WORKSPACE SKILLS
# ============================================================
# OpenClaw looks for skills in ~/.openclaw/workspace/skills/
# but we store them in /root/clawd/skills/ (baked into Docker image)
if [ -d "$SKILLS_DIR" ] && [ ! -e "$CONFIG_DIR/workspace/skills" ]; then
    mkdir -p "$CONFIG_DIR/workspace"
    ln -s "$SKILLS_DIR" "$CONFIG_DIR/workspace/skills"
    echo "Linked workspace skills: $SKILLS_DIR -> $CONFIG_DIR/workspace/skills"
fi

# ============================================================
# START GATEWAY
# ============================================================
echo "Starting OpenClaw Gateway..."
echo "Gateway will be available on port 18789"

rm -f /tmp/openclaw-gateway.lock 2>/dev/null || true
rm -f "$CONFIG_DIR/gateway.lock" 2>/dev/null || true

echo "Dev mode: ${OPENCLAW_DEV_MODE:-false}"

if [ -n "$OPENCLAW_GATEWAY_TOKEN" ]; then
    echo "Starting gateway with token auth..."
    exec openclaw gateway --port 18789 --verbose --allow-unconfigured --bind lan --token "$OPENCLAW_GATEWAY_TOKEN"
else
    echo "Starting gateway with device pairing (no token)..."
    exec openclaw gateway --port 18789 --verbose --allow-unconfigured --bind lan
fi
