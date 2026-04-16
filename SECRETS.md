# Nix Secrets Workflow (agenix)

This project uses `agenix` to manage secrets encrypted with SSH keys.

## 1. Add a new secret definition
Edit `secrets/secrets.nix` to define the new file and who can decrypt it:
```nix
"new-secret.age".publicKeys = [ lorcan optiplex ];
```

## 2. Create/Edit the encrypted file
Run this on your **Mac** (where your user SSH key is):
```bash
cd ~/nix-config/secrets
agenix -e new-secret.age
```
*Paste the secret value, save, and exit (:wq).*

## 3. Register the secret in Nix
Edit `modules/secrets.nix` to tell the system where to decrypt it:
```nix
age.secrets.new-secret = {
  file  = ../secrets/new-secret.age;
  owner = "lorcan";
};
```

## 4. Deploy
```bash
git add . && git commit -m "Add new-secret" && git push
rebuild-mac  # On Mac
# Or on OptiPlex: git pull && rebuild-server
```

## 5. Access the secret
Secrets are decrypted to:
- **Mac**: `/run/agenix.d/1/new-secret`
- **NixOS**: `/run/agenix/new-secret`
