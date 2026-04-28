# 🎸 Vibe-coding VM — Provisioner automatique

> Une seule commande pour transformer une VM Ubuntu 24.04 vierge en environnement
> de vibe-coding complet : VS Code dans le navigateur + Gemini CLI dans le terminal.

```
make deploy
# → https://<IP>:8080
```

---

## 📐 Architecture

```
Machine locale                         VM Ubuntu 24.04
─────────────────                      ──────────────────────────────────────
Makefile                               ┌─ Docker ──────────────────────────┐
  └─ ansible-playbook ──SSH──────────► │  code-server:8080 (HTTPS)         │
       provision.yml                   │    ├── ~/workspace (git clone)    │
                                       │    ├── extensions (3 pré-installées)│
                                       │    └── terminal → gemini CLI      │
                                       └───────────────────────────────────┘
                                            ufw : 22 + 8080 ouverts
```

## ✅ Prérequis

### Machine locale (control node)

| Outil | Version minimale | Installation |
|-------|-----------------|--------------|
| `ansible` | ≥ 2.14 | `pip install ansible` |
| `ansible` collection `community.general` | dernière | `ansible-galaxy collection install community.general` |
| `make` | tout | pré-installé Linux/Mac |
| `envsubst` | tout | `apt install gettext` / `brew install gettext` |
| `ssh` | tout | pré-installé |

### VM cible

- **OS** : Ubuntu 24.04 LTS (Noble Numbat)
- **CPU** : 2 vCPU minimum recommandé
- **RAM** : 2 Go minimum (4 Go recommandé)
- **Stockage** : 20 Go minimum
- **Réseau** : IP publique accessible, port 22 ouvert au départ
- **Accès** : utilisateur avec `sudo` sans mot de passe (typique chez les cloud providers)

---

## 🚀 Setup initial

### 1. Cloner ce repo

```bash
git clone https://github.com/your-org/vibe-vm-provisioner.git
cd vibe-vm-provisioner
```

### 2. Configurer la clé SSH

Si vous n'avez pas encore de paire de clés :

```bash
ssh-keygen -t ed25519 -C "vibe-vm" -f ~/.ssh/vibe-vm
ssh-copy-id -i ~/.ssh/vibe-vm.pub ubuntu@<TARGET_IP>
# Tester :
ssh -i ~/.ssh/vibe-vm ubuntu@<TARGET_IP> echo OK
```

### 3. Créer le fichier `.env`

```bash
cp .env.example .env
$EDITOR .env   # renseigner toutes les variables
```

| Variable | Description | Exemple |
|----------|-------------|---------|
| `TARGET_IP` | IP publique de la VM | `51.68.42.10` |
| `TARGET_USER` | Utilisateur SSH avec sudo | `ubuntu` |
| `SSH_KEY_PATH` | Chemin clé privée locale | `~/.ssh/vibe-vm` |
| `GEMINI_API_KEY` | Clé API Google Gemini | `AIza...` |
| `CS_PASSWORD` | Mot de passe VS Code | `MonP@ss!2024` |
| `WORKSPACE_REPO` | URL HTTPS du repo à cloner | `https://github.com/user/project.git` |

> **Repo privé ?** Utilisez un token PAT dans l'URL :
> `https://ghp_TOKEN@github.com/user/repo.git`

### 4. Installer les dépendances Ansible

```bash
ansible-galaxy collection install community.general
```

---

## ⚡ Commandes

```bash
make deploy    # Provisionne tout (≈ 5-8 min)
make status    # Vérifie l'état des containers
make logs      # Suit les logs de code-server en temps réel
make destroy   # Arrête et supprime code-server
make help      # Affiche toutes les cibles disponibles
```

---

## 🌐 Accès à VS Code

Après `make deploy` :

1. Ouvrir **`https://<TARGET_IP>:8080`** dans le navigateur
2. Accepter l'avertissement de certificat auto-signé
3. Entrer le mot de passe défini dans `CS_PASSWORD`
4. Le repo est ouvert dans `~/workspace`

### Utiliser Gemini CLI dans le terminal

Ouvrir le terminal intégré (`Ctrl+\``) :

```bash
gemini                         # mode interactif
gemini "explique ce fichier"   # mode one-shot
gemini --help                  # toutes les options
```

La clé API `GEMINI_API_KEY` est automatiquement injectée dans l'environnement shell.

---

## 📦 Ce qui est installé

| Composant | Version/Source |
|-----------|---------------|
| Docker CE | Dernière stable (repo officiel) |
| nvm | v0.39.7 |
| Node.js | LTS (`nvm install --lts`) |
| `@google/gemini-cli` | Dernière (npm global) |
| code-server | `codercom/code-server:latest` |
| Extension Python | `ms-python.python` |
| Extension ESLint | `dbaeumer.vscode-eslint` |
| Extension Prettier | `esbenp.prettier-vscode` |

---

## 🔒 Sécurité

- Aucun secret en clair dans les fichiers versionnés
- `.env` et `ansible/inventory.ini` sont dans `.gitignore`
- ufw activé : seuls les ports 22 et 8080 sont ouverts
- HTTPS auto-signé sur code-server (certificat généré au premier démarrage)
- Le token Git (si utilisé dans `WORKSPACE_REPO`) n'est jamais loggué

> Pour aller plus loin : ajoutez un reverse proxy (Nginx/Caddy) avec un certificat
> Let's Encrypt pour un HTTPS propre sur votre domaine.

---

## 🔧 Idempotence

Le playbook est entièrement idempotent. Vous pouvez le rejouer :

- Pour appliquer des changements de config
- Après une modification de `settings.json` ou `daemon.json`
- Pour réinstaller une extension manquante

```bash
make deploy   # Toujours sûr à relancer
```

---

## 🐛 Dépannage

**SSH refusé :**
```bash
ssh -i "$SSH_KEY_PATH" -v "$TARGET_USER@$TARGET_IP"
```

**code-server ne répond pas :**
```bash
make logs
make status
```

**Extensions non installées :**
```bash
ssh -i "$SSH_KEY_PATH" "$TARGET_USER@$TARGET_IP" \
  'docker exec code-server code-server --list-extensions'
```

**Rejouer uniquement le health check :**
```bash
ansible-playbook ansible/provision.yml --tags health -i ansible/inventory.ini
```

---

## 📄 Licence

MIT — libre d'utilisation et de modification.
