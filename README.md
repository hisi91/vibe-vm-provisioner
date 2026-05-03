# 🎸 Vibe-coding VM — Provisioner automatique

> Une seule commande pour transformer une VM Debian/Ubuntu vierge en environnement
> de vibe-coding complet : VS Code dans le navigateur (code-server natif) + Gemini CLI dans le terminal.

```bash
make deploy
# → http://<IP>:8080
```

---

## 📐 Architecture

```
Machine de contrôle (VM ou local)        VM cible (Debian 13)
─────────────────────────────────        ──────────────────────────────
Makefile                                 code-server :8080 (natif)
  └─ ansible-playbook ──SSH──────────►     ├── ~/workspace (git clone)
       provision.yml                        ├── Gemini CLI (terminal)
                                            ├── Extensions VS Code
                                            └── systemd (auto-restart)
```

---

## ✅ Prérequis

### Machine de contrôle

```bash
# Ansible
pip install ansible
ansible-galaxy collection install community.general

# envsubst (Linux — normalement déjà présent)
apt install gettext

# envsubst (Mac)
brew install gettext && brew link gettext --force
```

### VM cible

- **OS** : Debian 12/13 ou Ubuntu 22/24 LTS
- **CPU** : 1 vCPU minimum (2 recommandé)
- **RAM** : 1 Go minimum (2 Go recommandé)
- **Accès** : utilisateur `root` ou sudo sans mot de passe
- **Ports** : 22 ouvert au départ

---

## 🚀 Setup initial (une seule fois)

### 1. Cloner ce repo sur la machine de contrôle

```bash
git clone https://github.com/ton-user/vibe-vm-provisioner.git
cd vibe-vm-provisioner
```

### 2. Créer la clé SSH et la copier sur la VM cible

```bash
# Générer la clé (si pas déjà fait)
ssh-keygen -t ed25519 -f ~/.ssh/vibe-vm

# Copier sur la VM cible
ssh-copy-id -i ~/.ssh/vibe-vm.pub root@<TARGET_IP>

# Tester
ssh -i ~/.ssh/vibe-vm root@<TARGET_IP> echo "OK"
```

### 3. Créer le fichier `.env`

```bash
cp .env.example .env
nano .env
```

| Variable | Description | Exemple |
|----------|-------------|---------|
| `TARGET_IP` | IP publique de la VM cible | `216.128.156.17` |
| `TARGET_USER` | Utilisateur SSH (`root` sur Vultr/Debian) | `root` |
| `SSH_KEY_PATH` | Chemin vers la clé privée SSH | `~/.ssh/vibe-vm` |
| `GEMINI_API_KEY` | Clé API Google Gemini | `AIza...` |
| `CS_PASSWORD` | Mot de passe pour accéder à VS Code | `MonP@ss!2024` |
| `WORKSPACE_REPO` | URL HTTPS du repo git à cloner | `https://github.com/user/project.git` |

> **Repo privé ?** Inclure le token PAT dans l'URL :
> `https://ghp_TOKEN@github.com/user/repo.git`

---

## ⚡ Déploiement

```bash
make deploy
```

Durée : **3 à 5 minutes**. L'URL s'affiche à la fin :

```
✔  Provisioning terminé !
🌐  Accès VS Code : http://216.128.156.17:8080
🔑  Mot de passe  : voir CS_PASSWORD dans .env
```

---

## 🌐 Accès à VS Code

1. Ouvrir **`http://<TARGET_IP>:8080`** dans le navigateur
2. Entrer le mot de passe défini dans `CS_PASSWORD`
3. Le workspace git est ouvert dans `~/workspace`

---

## 🤖 Utiliser Gemini CLI

Dans le terminal intégré de VS Code (`Ctrl+\``) :

```bash
# Si gemini n'est pas trouvé au premier lancement
source ~/.bashrc

# Lancer Gemini CLI
gemini                          # mode chat interactif
gemini "explique ce fichier"    # question rapide
```

La clé `GEMINI_API_KEY` est automatiquement injectée dans `~/.bashrc` par Ansible.

---

## 🗂️ Structure du projet

```
vibe-vm-provisioner/
├── Makefile                      # make deploy / destroy / status / logs
├── .env.example                  # Template à copier en .env
├── .env                          # Secrets locaux (dans .gitignore)
├── .gitignore                    # Exclut .env et inventory.ini
├── ansible.cfg                   # Config Ansible (pipelining, SSH)
└── ansible/
    ├── inventory.ini.tpl         # Template → inventory.ini (via make)
    ├── inventory.ini             # Généré automatiquement (dans .gitignore)
    ├── provision.yml             # Playbook principal
    └── files/
        └── settings.json         # Settings VS Code (JSON pur, sans commentaires)
```

---

## 📦 Ce qui est installé sur la VM

| Composant | Détail |
|-----------|--------|
| `curl`, `git`, `unzip`, `build-essential` | Outils système |
| `nvm` v0.39.7 | Gestionnaire de versions Node |
| Node.js LTS | Via nvm |
| `@google/gemini-cli` | IA dans le terminal |
| `code-server` | VS Code natif dans le navigateur |
| Extension Python | `ms-python.python` |
| Extension ESLint | `dbaeumer.vscode-eslint` |
| Extension Prettier | `esbenp.prettier-vscode` |
| `ufw` | Pare-feu (ports 22 et 8080 ouverts) |

---

## 🔧 Commandes disponibles

```bash
make deploy    # Provisionne la VM complète
make status    # Vérifie l'état de code-server (systemd)
make logs      # Affiche les logs de code-server en temps réel
make destroy   # Arrête code-server
make help      # Liste toutes les commandes
```

---

## ♻️ Idempotence

Le playbook est **entièrement rejouable** sans casser l'existant :

```bash
make deploy   # Toujours sûr à relancer
```

Utile pour : appliquer un nouveau `settings.json`, ajouter une extension,
mettre à jour la config, ou réparer un service cassé.

---

## 🔒 Sécurité

- `.env` et `ansible/inventory.ini` dans `.gitignore` — jamais committé
- Mot de passe code-server défini dans `.env` uniquement
- `ufw` activé : seuls les ports 22 et 8080 sont accessibles
- Token Git (si utilisé dans `WORKSPACE_REPO`) jamais loggué

---

## 🐛 Dépannage

**Vérifier que code-server tourne :**
```bash
ssh -i ~/.ssh/vibe-vm root@<TARGET_IP> 'systemctl status code-server@root'
```

**Voir les logs :**
```bash
make logs
# ou directement :
ssh -i ~/.ssh/vibe-vm root@<TARGET_IP> 'journalctl -u code-server@root -f'
```

**Redémarrer code-server :**
```bash
ssh -i ~/.ssh/vibe-vm root@<TARGET_IP> 'systemctl restart code-server@root'
```

**gemini introuvable dans le terminal VS Code :**
```bash
source ~/.bashrc
gemini
```

**Inventory vide / hosts not matched :**
```bash
cat ansible/inventory.ini   # doit contenir l'IP
make deploy                 # le regénère automatiquement
```

---

## 📄 Licence

MIT