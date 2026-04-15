# Admin GCP Setup SOP — gws OAuth Client

Admin performs this **once** on their Mac. The final output is a `client_secret.json` file that gets stored as a Worker Secret (`GWS_CLIENT_SECRET_JSON`) and shared by all deployed bots.

## Goal

- Sign into Google Cloud SDK with `gcloud auth login`
- Run `gws auth setup` to create a GCP project + enable Workspace APIs
- Manually create an OAuth client in Google Cloud Console
- Download `client_secret.json`

This is a general SOP, not tied to one specific Google account.

---

## 1. Run `gcloud auth login`

If `gcloud` is not authenticated yet, run:

```bash
gcloud auth login
```

A browser window will open. Sign in with your target Google account and approve access.

### 1.1 Verify `gcloud` login

```bash
gcloud auth list
```

Success means the target account appears and is active (`*`).

---

## 2. Run `gws auth setup`

After `gcloud` is authenticated, run:

```bash
gws auth setup
```

### 2.1 Expected setup stages

The setup flow may include:

- checking `gcloud`
- checking current Google authentication
- selecting a Google account
- selecting or creating a GCP project
- enabling Workspace APIs
- attempting OAuth setup

### 2.2 Account selection

If setup shows available Google accounts:

- choose the target Google account
- avoid `Login with new account` unless the target account is missing

### 2.3 Project selection

Recommended default path:

- choose `Create new project`
- enter a new project ID (e.g. `gws-cli-oc`)

Alternative path:

- choose an existing project if you intentionally want to reuse one

### 2.4 API selection

When the API selection screen appears:

- choose the Google Workspace APIs you need
- if unsure, choose all relevant Workspace APIs required by your workflow

### 2.5 What `gws auth setup` completes automatically

- confirming `gcloud` is installed
- confirming Google account auth exists
- creating or selecting a project
- enabling APIs

### 2.6 What `gws auth setup` does NOT complete

It will stop and require manual Google Cloud Console steps for:

- OAuth brand / consent configuration
- OAuth client creation
- adding test users

Continue to Step 3 to complete these manually.

---

## 3. Manual OAuth Setup in Google Cloud Console

### 3.1 OAuth brand / consent configuration

Open the target project in Google Cloud Console.

**Path**: Google Auth Platform → Branding / Brand

Fill in the required fields:

- App name
- User support email
- User type (`External` is the usual choice for personal/testing use)
- Contact email
- accept the required Google API Services policy / terms

**Recommended process**:

1. open the branding page for the target project
2. fill app name
3. choose the support email
4. choose `External` if the app is for non-internal testing
5. fill the contact email
6. accept the required policy / consent
7. save / create the brand configuration

**Important**:

- if the project is in testing mode, that is normal for personal use
- branding must exist before OAuth client creation works cleanly

### 3.2 OAuth client creation

After the brand / consent configuration exists, create the OAuth client.

**Path**: Google Auth Platform → Clients / OAuth clients → Create client

**Recommended values**:

- Application type: `Desktop app`
- Name: choose a clear name such as `gws CLI`

**Recommended process**:

1. open the Clients page
2. click `Create client`
3. choose `Desktop app`
4. enter the client name
5. create the client
6. **Download the JSON** (this is your `client_secret.json`)

Save the downloaded JSON somewhere safe — you will need it when deploying bots.

### 3.3 Adding test users

If the OAuth app is still in testing mode, add test users.

Without this, login may fail with errors such as:

- `Access blocked`
- `Error 403: access_denied`
- app has not completed Google verification

**Path**: Google Auth Platform → Audience / Target audience → Test users

**Recommended process**:

1. open the Audience / Target audience page
2. find the test users section
3. click `Add users`
4. enter the Google account email(s) that should be allowed to authenticate
5. save the change
6. confirm the target email now appears in the test user list

**This step is especially important for**:

- personal testing
- unverified apps
- new OAuth clients that are not published

Add all users who will be paired with the deployed bots.

---

## 4. Verify

### 4.1 Verify `gcloud`

```bash
gcloud auth list
```

### 4.2 Verify `client_secret.json`

You should have a file like `client_secret_<long-id>.apps.googleusercontent.com.json`. It should contain:

```json
{
  "installed": {
    "client_id": "...",
    "project_id": "...",
    "client_secret": "...",
    "redirect_uris": ["http://localhost"]
  }
}
```

---

## 5. Next step: Deploy bots

You now have `client_secret.json`. Use it when deploying bots with the `deploy-openclaw` skill.

Each bot stores this JSON as a Worker Secret (`GWS_CLIENT_SECRET_JSON`). The same JSON can be reused for all bots deployed with the same GCP project.

---

## 6. Minimal success checklist

A run is successful if:

- `gcloud auth login` completes successfully
- `gcloud auth list` shows the intended active account
- `gws auth setup` completes project/account/API stages
- OAuth brand / consent is configured
- OAuth client (Desktop app) is created and `client_secret.json` is downloaded
- Test users are added (for unverified apps)
