# Git SSH Setup

Use this guide to configure GitHub SSH access for this repository and its nested app repositories.

## Important distinction

- [`.github`](d:/Development/saas_platform/.github) is a folder inside this repository.
  It is used for repository automation such as GitHub Actions workflows, issue templates, and pull request templates.

- `https://github.com/settings/keys` is your personal GitHub account SSH key settings page.
  It is used to register your machine's public SSH key so GitHub can authenticate you when you clone, pull, or push over SSH.

These two are related to GitHub, but they are used for completely different purposes.

## Why SSH is needed

This project uses SSH-based Git URLs in [`.gitmodules`](d:/Development/saas_platform/.gitmodules), for example:

- `git@github.com:chikuu29/OWN_OAUTH_INDENTITY_PROVIDER_BACKEND.git`
- `git@github.com:chikuu29/OWN_OAUTH_INDENTITY_PROVIDER_FRONTEND.git`
- `git@github.com:chikuu29/workspace-platform-fastapi.git`
- `git@github.com:chikuu29/workspace-platform.git`

That means your machine needs a GitHub SSH key configured before `git pull`, `git push`, or submodule commands will work.

## 1. Check whether you already have an SSH key

In PowerShell:

```powershell
Get-ChildItem $HOME\.ssh
```

If you already have files like `id_ed25519` and `id_ed25519.pub`, you can usually reuse them.

## 2. Create a new SSH key if needed

```powershell
ssh-keygen -t ed25519 -C "your-email@example.com"
```

Press Enter to use the default path:

```text
C:\Users\<your-user>\.ssh\id_ed25519
```

You can set a passphrase or leave it empty.

## 3. Start the SSH agent

```powershell
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
```

## 4. Add your key to the SSH agent

```powershell
ssh-add $HOME\.ssh\id_ed25519
```

## 5. Copy the public key

```powershell
Get-Content $HOME\.ssh\id_ed25519.pub
```

Copy the full output.

## 6. Add the key to GitHub

Open:

```text
https://github.com/settings/keys
```

Then:

1. Click `New SSH key`
2. Give it a name like `Work Laptop` or `Dev Machine`
3. Paste the public key
4. Save

## 7. Test the GitHub SSH connection

```powershell
ssh -T git@github.com
```

Expected result:

```text
Hi <username>! You've successfully authenticated...
```

## 8. Verify Git remotes

From the root repo:

```powershell
git remote -v
```

For nested repos:

```powershell
git -C .\apps\identity_server\backend remote -v
git -C .\apps\identity_server\web remote -v
git -C .\apps\work_space\backend remote -v
git -C .\apps\work_space\web remote -v
```

If you need to switch a repo remote to SSH:

```powershell
git remote set-url origin git@github.com:<owner>/<repo>.git
```

Example:

```powershell
git -C .\apps\work_space\web remote set-url origin git@github.com:chikuu29/workspace-platform.git
```

## 9. Sync submodules after SSH setup

After SSH access works, run:

```powershell
git submodule sync --recursive
git submodule update --init --recursive
```

## Common issues

### Permission denied (publickey)

Usually means:

- the SSH key was not added to GitHub
- the SSH agent is not running
- the wrong key is being used

Try:

```powershell
ssh-add -l
```

If no identities are listed, add the key again.

### Wrong GitHub account

If multiple keys are used on the same machine, add an SSH config file:

Path:

```text
$HOME\.ssh\config
```

Example:

```sshconfig
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
```

## Useful commands

```powershell
ssh -T git@github.com
git submodule sync --recursive
git submodule update --init --recursive
git status
git remote -v
```
