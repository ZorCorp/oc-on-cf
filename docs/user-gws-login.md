# User Google Workspace Login Prompt

After the bot is deployed and paired (both Telegram and OpenClaw Dashboard), send this prompt to your user.

The user should copy the block below and paste it to the bot as a single message. The bot's agent will follow the SOP step by step to complete Google OAuth via agent-browser.

---

## Prompt to send to user

> Please paste the following message to the bot on Telegram (or via the OpenClaw Dashboard chat). The bot's agent will guide you through Google Workspace login automatically.

```markdown
# gws auth login + agent-browser profile SOP

## Goal
Only cover:
- creating / reusing an `agent-browser` Google profile
- completing `gws auth login`

This is a general SOP, not tied to one specific Google account.

---

## 1. Create / reuse the browser profile
Use a persistent profile so Google login state can be reused.

### 1.1 Create the profile directory
```bash
mkdir -p ~/.config/agent-browser/google-profile
```

### 1.2 Stop any existing agent-browser daemon
This avoids profile mismatch / "profile ignored" issues.

```bash
agent-browser close || true
```

### 1.3 Open Google sign-in with the target profile
```bash
agent-browser --profile ~/.config/agent-browser/google-profile open 'https://accounts.google.com/'
```

### 1.4 Inspect the page before acting
Use snapshot to see the current interactive elements and refs.

```bash
agent-browser --profile ~/.config/agent-browser/google-profile snapshot -i -c -d 6
```

---

## 2. If Google login is required, use this detailed login flow

### 2.1 Email page
If the page shows an email field such as:
- `Email or phone`
- `輸入電郵地址或電話`

Then:
1. fill the email field with the target Google account
2. click `Next`

Example pattern:
```bash
agent-browser --profile ~/.config/agent-browser/google-profile fill @e1 'TARGET_EMAIL'
agent-browser --profile ~/.config/agent-browser/google-profile click @e2
```

Always use the refs from the latest snapshot instead of assuming `@e1/@e2` never change.

### 2.2 Password page
If the page shows a password field such as:
- `Enter your password`
- `輸入你的密碼`

Then:
1. fill the password field
2. click `Next`

### 2.3 Account chooser page
If Google shows multiple saved accounts:
- choose the target Google account button
- do not choose `Use another account` unless the target account is missing

### 2.4 Device verification / challenge page
Google may require extra verification even after password entry.
Possible cases:

#### Case A: simple approval prompt
- approve sign-in on a trusted phone
- then return to the browser and continue

#### Case B: number matching
- browser shows one number
- trusted device shows multiple numbers
- choose the same number on the trusted device

If the automation snapshot does not show the number clearly:
1. take another snapshot after waiting a moment
2. if still missing, use screenshot instead of snapshot
3. read the number from the screenshot

### 2.5 Re-check page state after each transition
After every important click or challenge, run a fresh snapshot:

```bash
agent-browser --profile ~/.config/agent-browser/google-profile snapshot -i -c -d 6
```

### 2.6 Confirm login success
Login is considered successful when the browser reaches a signed-in Google page, such as:
- Google Account
- myaccount.google.com
- another signed-in Google page with the account visible

A useful verification command is:
```bash
agent-browser --profile ~/.config/agent-browser/google-profile open 'https://myaccount.google.com/'
agent-browser --profile ~/.config/agent-browser/google-profile snapshot -i -c -d 6
```

If you see Google Account menus and account controls, the profile is logged in.

### 2.7 Reuse the same profile afterwards
After login succeeds, keep using this same profile for all Google / GCP / OAuth flows.

Pattern:
```bash
agent-browser close || true
agent-browser --profile ~/.config/agent-browser/google-profile open '<url>'
```

---

## 3. Run `gws auth login`
Run:

```bash
gws auth login --scopes "https://www.googleapis.com/auth/drive,https://www.googleapis.com/auth/documents,https://www.googleapis.com/auth/spreadsheets,https://www.googleapis.com/auth/gmail.modify,https://www.googleapis.com/auth/calendar"
```

### 3.1 Important terminal rules
- keep the `gws auth login` terminal/session alive
- it will print an OAuth URL
- do not close the command after the URL appears
- do not restart the command unless the flow fully fails

### 3.2 Capture the OAuth URL
The terminal should print something like:
- `Open this URL in your browser to authenticate:`
- followed by a long Google OAuth URL

Copy / reuse that exact URL.

---

## 4. Open the OAuth URL with the same profile
Before opening the URL, close the current agent-browser daemon to make sure the correct profile is used.

```bash
agent-browser close || true
```

Then open the printed OAuth URL:

```bash
agent-browser --profile ~/.config/agent-browser/google-profile open "<auth_url>"
```

After opening, inspect the page:

```bash
agent-browser --profile ~/.config/agent-browser/google-profile snapshot -i -c -d 8
```

---

## 5. Complete the Google OAuth flow
Follow the actual page state.
Do not assume the flow is always identical.

### 5.1 If account chooser appears
- choose the correct Google account

### 5.2 If device verification appears
- complete the required challenge on the trusted device
- if it is number matching, make sure the trusted device chooses the same number shown in browser
- after the trusted-device step finishes, return to browser and continue

### 5.3 If consent page appears
The page may show:
- `Account Permissions`
- `Allow` / `允許`
- `Deny` / `拒絕`

Action:
- click `Allow` / `允許`

### 5.4 Wait if the button is temporarily disabled
Sometimes `Allow` appears but is disabled while the page is still loading.
In that case:
1. wait a moment
2. snapshot again
3. click only when the button becomes enabled

### 5.5 Do not assume these always exist
Do not assume the flow always has:
- warning page
- two Continue buttons
- scope checkboxes
- no 2-step challenge

Google may show different flows on different runs.

---

## 6. Wait for automatic localhost callback
After approval, `gws` should complete automatically through localhost callback.
Normally you do not need to manually paste any code.

### 6.1 Expected terminal result
The `gws auth login` terminal should finish with output that includes fields such as:
- `account`
- `credentials_file`
- `message: Authentication successful`
- `status: success`

Credentials are usually saved to:
- `~/.config/gws/credentials.enc`

---

## 7. Verify
Run:

```bash
gws drive files list --params '{"pageSize":1}'
```

If this works, `gws auth login` is good.

---

## 8. Minimal success checklist
A run is successful only if all of these are true:
- the browser profile is logged into the intended Google account
- `gws auth login` prints an OAuth URL and stays alive during the flow
- the OAuth URL is opened with the same browser profile
- any device verification is completed successfully
- the consent page is approved
- `gws auth login` exits successfully
- `gws drive files list --params '{"pageSize":1}'` works
```

---

## Notes for Admin

- User may need to provide their Google password and complete 2FA on their trusted device during the flow.
- If Google blocks the login (suspicious activity, CAPTCHA), the user must retry or complete extra verification on their phone.
- Credentials are saved inside the container at `~/.config/gws/credentials.enc` and automatically backed up to R2 (persists across container restarts).
