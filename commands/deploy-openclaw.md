---
name: deploy-openclaw
description: >
  Deploy a new OpenClaw AI Bot on Cloudflare Workers + Containers.
  Handles full setup from scratch on macOS — installs dependencies,
  creates Cloudflare resources, deploys, and configures Telegram.
compatibility:
  tools:
    - Bash
    - Read
    - WebFetch
---

# Deploy OpenClaw on Cloudflare (macOS)

You are deploying an OpenClaw AI Bot on Cloudflare. Follow every step in order. The bundled `moltworker/` folder contains all source code — no git clone needed.

## Step 0: Prerequisites check and auto-fix

Check each tool. If missing, install it. Run checks sequentially.

### 0.1 Homebrew

```bash
brew --version
```

If not found:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

On Apple Silicon, also run:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### 0.2 Node.js (>= 18)

```bash
node --version
```

If not found or version < 18:

```bash
brew install node
```

### 0.3 wrangler CLI

```bash
wrangler --version
```

If not found:

```bash
npm install -g wrangler
```

### 0.4 Docker

```bash
docker --version
```

If not found:

```bash
brew install --cask docker
```

Then check daemon:

```bash
docker ps 2>&1
```

If "Cannot connect" or "no such file", start Docker:

```bash
open -a Docker
```

Wait up to 60 seconds, retrying `docker ps` every 5 seconds until it works.

### 0.5 wrangler login

```bash
wrangler whoami 2>&1
```

If not logged in:

```bash
wrangler login
```

Tell user: "A browser window will open. Please log in to your Cloudflare account and authorize wrangler."

### 0.6 Cloudflare API Token

Check if user has a CF API Token stored:

```bash
echo $CLOUDFLARE_API_TOKEN
```

If empty, open the token creation page for the user:

```bash
open "https://dash.cloudflare.com/profile/api-tokens"
```

Then tell user:

> I've opened the Cloudflare API Token page. Please:
> 1. Click **Create Token**
> 2. Use the **Edit Cloudflare Workers** template → click **Use template**
> 3. Under Permissions, click **+ Add more** and add:
>    - **Account → AI Gateway → Edit**
>    - **Account → Workers R2 Storage → Edit**
>    - **Account → Billing → Read**
> 4. Under Account Resources: **Include → All accounts** (or select your account)
> 5. Under Zone Resources: **Include → All zones**
> 6. Leave Client IP and TTL as default (empty)
> 7. Click **Continue to summary** → **Create Token**
> 8. Copy the token and give it to me
>
> This token is reusable for all future deployments.

Store as `{CF_API_TOKEN}`. Recommend user save it:

```bash
export CLOUDFLARE_API_TOKEN="{CF_API_TOKEN}"
```

### 0.7 Telegram Bot Token

Ask user:

> Do you already have a Telegram Bot Token? If not:
> 1. Open Telegram → search **@BotFather**
> 2. Send `/newbot`
> 3. Follow prompts to name your bot
> 4. Copy the token (like `8622764702:AAGk...`)
> 5. Give me the token

Store as `{TELEGRAM_TOKEN}`.

### 0.8 AI Model (optional)

Ask user:

> Which AI model? (Enter for default: `@cf/nvidia/nemotron-3-120b-a12b`)

Store as `{USER_MODEL}`.

### 0.9 Instance name (optional)

Ask user:

> Name for this bot? (Enter for default: `openclaw`)
> Note: only lowercase letters, numbers, and hyphens. No underscores.

Store as `{NAME}`.

## Step 1: Derive variables

```bash
wrangler whoami 2>&1
```

Parse all account IDs from the output (32-char hex strings). If multiple accounts found, show them to the user and ask which one to use. If only one, use it automatically.

```bash
GATEWAY_TOKEN=$(openssl rand -hex 32)
```

### Verify account plan

Check that the account has Workers Paid Plan (required for Containers):

```bash
node -e "
const https = require('https');
const opts = {
  hostname: 'api.cloudflare.com',
  path: '/client/v4/accounts/${ACCOUNT_ID}/subscriptions',
  headers: { 'Authorization': 'Bearer ${CF_API_TOKEN}' }
};
https.get(opts, res => {
  let d=''; res.on('data', c => d += c);
  res.on('end', () => {
    try {
      const r = JSON.parse(d);
      if (r.success && r.result) {
        const workers = r.result.find(s => s.rate_plan?.public_name?.includes('Workers'));
        if (workers && workers.state === 'Paid') {
          console.log('Workers plan: ' + workers.rate_plan.public_name + ' (OK)');
        } else {
          console.log('NO_WORKERS_PLAN');
        }
      } else { console.log('CHECK_FAILED'); }
    } catch(e) { console.log('CHECK_FAILED'); }
  });
});
"
```

If output is `NO_WORKERS_PLAN`, tell user:

> Your Cloudflare account does not have a Workers Paid Plan. This is required for Containers.
> Please go to CF Dashboard → Workers & Pages → Plans → upgrade to Workers Paid ($5/month).

If output is `CHECK_FAILED`, the API Token may not have Billing Read permission. You can skip this check and proceed — deployment will fail later if the plan is missing.

Get workers subdomain:

```bash
node -e "
const https = require('https');
const opts = {
  hostname: 'api.cloudflare.com',
  path: '/client/v4/accounts/${ACCOUNT_ID}/workers/subdomain',
  headers: { 'Authorization': 'Bearer ${CF_API_TOKEN}' }
};
https.get(opts, res => {
  let d=''; res.on('data', c => d += c);
  res.on('end', () => { try { console.log(JSON.parse(d).result.subdomain); } catch(e) { console.log(''); } });
});
"
```

If subdomain is empty, ask user:

> What is your Cloudflare Workers subdomain? Find it at: CF Dashboard → Workers & Pages → Overview (bottom shows `xxx.workers.dev`)

Computed values:

- `WORKER_URL` = `https://{NAME}.{SUBDOMAIN}.workers.dev`
- `R2_BUCKET` = `{NAME}-data`
- `GATEWAY_ID` = `{NAME}-gateway`
- `MODEL_ID` = `workers-ai/{USER_MODEL}`

Save `GATEWAY_TOKEN` — user needs it to access the dashboard.

## Step 2: Prepare source code

```bash
cp -r {SKILL_DIR}/moltworker {WORK_DIR}
cd {WORK_DIR}
```

## Step 3: Modify files

Only 2 sed commands needed. Everything else is handled by Wrangler Secrets at runtime.

```bash
cd {WORK_DIR}
sed -i '' 's/moltbot-sandbox/{NAME}/g' wrangler.jsonc
sed -i '' 's/moltbot-data/{NAME}-data/g' wrangler.jsonc
```

## Step 4: Install dependencies

```bash
cd {WORK_DIR}
npm install
```

## Step 5: Create Cloudflare resources

### 5a. Create R2 Bucket (auto)

```bash
CLOUDFLARE_ACCOUNT_ID=${ACCOUNT_ID} wrangler r2 bucket create {R2_BUCKET}
```

### 5b. Create AI Gateway (auto)

```bash
node -e "
const https = require('https');
const data = JSON.stringify({id:'{GATEWAY_ID}',name:'{GATEWAY_ID}',collect_logs:true,rate_limiting_interval:0,rate_limiting_limit:0,rate_limiting_technique:'fixed',cache_ttl:0,cache_invalidate_on_update:true});
const opts = {
  hostname: 'api.cloudflare.com',
  path: '/client/v4/accounts/${ACCOUNT_ID}/ai-gateway/gateways',
  method: 'POST',
  headers: { 'Authorization': 'Bearer ${CF_API_TOKEN}', 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) }
};
const req = https.request(opts, res => {
  let d=''; res.on('data', c => d += c);
  res.on('end', () => { const r = JSON.parse(d); console.log(r.success ? 'AI Gateway created' : r.errors?.[0]?.message || 'Already exists'); });
});
req.write(data); req.end();
"
```

### 5c. Create AI Gateway Authentication Token (manual — no API available)

Open the gateway settings page for the user:

```bash
open "https://dash.cloudflare.com/${ACCOUNT_ID}/ai/ai-gateway/gateways/{GATEWAY_ID}"
```

Tell user:

> I've opened the AI Gateway page. Please:
> 1. Click **Settings** tab
> 2. Find **Authenticated Gateway** section → click **Create authentication token**
> 3. Token name: enter `{NAME}`
> 4. Keep defaults (Permission: AI Gateway → Run, Account: your account)
> 5. Click **Create Token**
> 6. Copy the token and give it to me
> 7. Then **enable the toggle** next to "Authenticated Gateway" to turn on authentication

Store as `{AIG_TOKEN}`.

### 5d. Create R2 API Token (optional, manual — no API available)

Open R2 token page for user:

```bash
open "https://dash.cloudflare.com/${ACCOUNT_ID}/r2/api-tokens"
```

Tell user:

> I've opened the R2 API Token page. This is optional but recommended (keeps data across container restarts). Please:
> 1. Click **Create Account API Token**
> 2. Token name: `{NAME}-r2`
> 3. Permission: **Object Read & Write**
> 4. Select **Apply to specific buckets only** → choose `{R2_BUCKET}`
> 5. TTL: **Forever**
> 6. Click **Create Account API Token**
> 7. Give me the **Access Key ID** and **Secret Access Key**
>
> Or type "skip" to skip R2 persistence.

## Step 6: Set secrets

Run each from `{WORK_DIR}`. If `wrangler secret put` fails, use `wrangler versions secret put` as fallback.

```bash
cd {WORK_DIR}
echo "sk-ant-dummy-bypass-key-not-real" | wrangler secret put ANTHROPIC_API_KEY
echo "{AIG_TOKEN}" | wrangler secret put CLOUDFLARE_AI_GATEWAY_API_KEY
echo "${ACCOUNT_ID}" | wrangler secret put CF_AI_GATEWAY_ACCOUNT_ID
echo "{GATEWAY_ID}" | wrangler secret put CF_AI_GATEWAY_GATEWAY_ID
echo "{MODEL_ID}" | wrangler secret put CF_AI_GATEWAY_MODEL
echo "${GATEWAY_TOKEN}" | wrangler secret put MOLTBOT_GATEWAY_TOKEN
echo "{TELEGRAM_TOKEN}" | wrangler secret put TELEGRAM_BOT_TOKEN
echo "{WORKER_URL}" | wrangler secret put WORKER_URL
echo "true" | wrangler secret put DEV_MODE
echo "true" | wrangler secret put DEBUG_ROUTES
echo "${ACCOUNT_ID}" | wrangler secret put CF_ACCOUNT_ID
echo "{R2_BUCKET}" | wrangler secret put R2_BUCKET_NAME
```

If R2 keys available:

```bash
echo "{R2_ACCESS_KEY}" | wrangler secret put R2_ACCESS_KEY_ID
echo "{R2_SECRET_KEY}" | wrangler secret put R2_SECRET_ACCESS_KEY
```

## Step 7: Deploy

```bash
cd {WORK_DIR}
npm run deploy
```

Takes 5-15 minutes on first run (Docker build + push + deploy). Ensure Docker is running.

## Step 8: Wait for container provisioning

After deploy completes, wait **2 minutes** for Cloudflare to finish provisioning the container (pulling image, starting VM, initializing sandbox runtime). Do NOT attempt health checks or trigger the container during this time.

```bash
sleep 120
```

## Step 9: Set Telegram webhook and pair

```bash
curl -s "https://api.telegram.org/bot{TELEGRAM_TOKEN}/setWebhook?url={WORKER_URL}/telegram"
```

1. Trigger container:
```bash
curl -s --max-time 10 "{WORKER_URL}/" > /dev/null
```

2. Wait 1-3 minutes. Poll every 15 seconds:
```bash
curl -s --max-time 10 "{WORKER_URL}/debug/gateway-api?path=/health"
```
Ready when response does NOT contain "not listening".

3. Tell user:
> Your bot is ready! Send **"hi"** to your bot in Telegram now.
> The bot will reply with a pairing code (like `H2YPBRTM`).
> Give me the pairing code.

4. When user provides the code, approve it:
```bash
curl -s --max-time 15 "{WORKER_URL}/debug/cli?cmd=openclaw+pairing+approve+telegram+{CODE}"
```

5. Confirm to user:
> Pairing complete! Your bot is ready. Try sending a message.

## Final output

Open both pages for the user:

```bash
open "{WORKER_URL}/"
open "{WORKER_URL}/_admin/"
```

Then tell user:

> ✅ **OpenClaw Bot deployed!**
>
> I've opened two pages for you. Follow these steps to connect:
>
> **Step 1.** Go to the **Dashboard** page (`{WORKER_URL}/`)
> - Paste this Gateway Token into the "網關令牌" field:
>   `{GATEWAY_TOKEN}`
> - Click **"連接"**
> - It will show "Pairing required" — this is normal
>
> **Step 2.** Go to the **Admin Panel** page (`{WORKER_URL}/_admin/`)
> - Click **"Refresh"** next to Pending Pairing Requests
> - You will see a **Pending Pairing Request** appear
> - Click **"Approve"** (or **"Approve All"**)
>
> **Step 3.** Go back to the **Dashboard** page
> - It should now be connected!
>
> **Save this Gateway Token for later:**
> `{GATEWAY_TOKEN}`
>
> Your Telegram bot is also ready — send it a message to start chatting!

## Troubleshooting

- Container not starting → `curl -s "{WORKER_URL}/debug/processes?logs=true"`
- Check secrets → `curl -s "{WORKER_URL}/debug/env"`
- View config → `curl -s "{WORKER_URL}/debug/container-config"`
- "origin not allowed" → WORKER_URL secret not set correctly
- Telegram no response → `curl -s "https://api.telegram.org/bot{TELEGRAM_TOKEN}/getWebhookInfo"`
- "openclaw requires Node >= X" → Dockerfile Node version too old
- Onboard hangs → ANTHROPIC_API_KEY secret not set
- `wrangler secret put` fails → use `wrangler versions secret put` then `npm run deploy`
