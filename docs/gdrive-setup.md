# Google Drive Service Account Setup (One-Time)

The shared workspace uses a Google Drive service account so team members don't need individual rclone setup.

## 1. Create a GCP Service Account

1. Go to [GCP Console → IAM → Service Accounts](https://console.cloud.google.com/iam-admin/service-accounts)
2. Select or create a project (e.g. `darkmatter-openclaw`)
3. Click **Create Service Account**
   - Name: `openclaw-workspace-sync`
   - ID: `openclaw-workspace-sync`
4. Skip roles (no GCP permissions needed — only Drive API)
5. Click **Done**

## 2. Create a JSON Key

1. Click the service account → **Keys** tab
2. **Add Key → Create New Key → JSON**
3. Download the JSON file

## 3. Enable the Drive API

1. Go to [APIs & Services → Library](https://console.cloud.google.com/apis/library)
2. Search for **Google Drive API**
3. Click **Enable**

## 4. Share the Folder

1. Open [the workspace folder](https://drive.google.com/drive/folders/12VTEdvFB6CyoGvrbWsVhUGqPMy_S2j6X)
2. Click **Share**
3. Add the service account email (from the JSON key, field `client_email`) as **Editor**

## 5. Store the Key in Sops

```bash
# From the repo root:
sops secrets/gdrive-sa-key.yaml
```

Add:
```yaml
gdrive_sa_key_json: |
    <paste entire JSON key file contents here>
```

Save and commit. GitHub Actions will re-encrypt for all team members.

## 6. Enable in Nix Config

```nix
openclaw-dm = {
  sharedWorkspace.enable = true;
  # folderId defaults to the team folder
};
```

That's it. `darwin-rebuild switch` will configure rclone automatically.
