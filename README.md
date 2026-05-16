# 🎸 Vibe-coding VM — Provisioner automatique

> Une seule commande depuis ta machine locale pour transformer une VM Debian/Ubuntu
> vierge en environnement de vibe-coding complet : VS Code dans le navigateur +
> Gemini CLI + Ruflo (orchestrateur multi-agents Claude).

```bash
./bootstrap.sh <IP_VM_ANSIBLE>
# → http://<IP_VM_CIBLE>:8080
```

---

## 📐 Architecture

```
Ta machine locale
  └── ./bootstrap.sh 45.77.228.140
        │
        ├── Demande interactive des infos (.env)
        ├── SSH → VM Ansible (45.77.228.140)
        │     ├── apt + ansible + community.general
        │     ├── git clone du repo
        │     ├── ssh-keygen → ~/.ssh/vibe-vm
        │     ├── ssh-copy-id → VM cible
        │     ├── écriture du .env
        │     └── make deploy
        │           └── SSH → VM cible (ex: 173.199.90.75)
        │                 ├── paquets système
        │                 ├── nvm + Node LTS
        │                 ├── Gemini CLI
        │                 ├── TypeScript
        │                 ├── Ruflo + agentic-flow
        │                 ├── code-server natif (systemd)
        │                 ├── settings.json + extensions VS Code
        │                 └── ufw (ports 22 + 8080)
        │
        └── ✔ http://<IP_VM_CIBLE>:8080
```

---

## ✅ Prérequis

### Ta machine locale (point de départ)

| Outil | Vérification |
|-------|-------------|
| `ssh` | `ssh -V` |
| `scp` | `scp -h` |
| Clé SSH vers VM Ansible | `ls ~/.ssh/id_ed25519` |

### VM Ansible (machine de contrôle)

- Debian 12/13 ou Ubuntu 22/24
- Accès SSH root depuis ta machine locale
- Accès internet (pour installer Ansible et cloner le repo)

### VM cible (machine provisionnée)

- Debian 12/13 ou Ubuntu 22/24
- Accès SSH root depuis la VM Ansible
- **Ports ouverts** : 22 (SSH) + 8080 (VS Code)
- 2 vCPU / 2 Go RAM minimum recommandé

---

## 🚀 Déploiement complet — de A à Z

### Étape 1 — Cloner ce repo sur ta machine locale

```bash
git clone https://github.com/hisi91/vibe-vm-provisioner.git
cd vibe-vm-provisioner
chmod +x bootstrap.sh
```

### Étape 2 — Lancer le bootstrap

```bash
# Minimal (user=root, clé=~/.ssh/id_ed25519)
./bootstrap.sh <IP_VM_ANSIBLE>

# Avec user custom
./bootstrap.sh <IP_VM_ANSIBLE> ubuntu

# Avec clé SSH spécifique
./bootstrap.sh <IP_VM_ANSIBLE> root ~/.ssh/ma-cle
```

Le script te demande interactivement :

```
📝 Configuration de l'environnement

  IP de la VM cible             → ex: 173.199.90.75
  Utilisateur SSH VM cible      → root (défaut)
  Clé API Google Gemini         → https://aistudio.google.com/app/apikey
  Clé API Anthropic (Ruflo)     → https://console.anthropic.com/settings/keys
  Mot de passe VS Code          → min 8 caractères
  URL repo Git workspace        → https://github.com/user/project.git
```

Puis affiche un récapitulatif et demande confirmation avant de lancer.

### Étape 3 — Cas particulier : copie manuelle de la clé SSH

Si la VM cible n'accepte pas l'auth par mot de passe, le script affiche :

```
⚠  Copie automatique impossible.
   Copie manuelle de cette clé sur 173.199.90.75 :
ssh-ed25519 AAAA...
```

Dans ce cas, connecte-toi sur la VM cible et colle la clé :

```bash
# Depuis ta machine locale ou la VM Ansible
ssh root@<IP_VM_CIBLE>

# Sur la VM cible
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA... vibe-coding-provisioner" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit

# Tester depuis la VM Ansible
ssh -i ~/.ssh/vibe-vm root@<IP_VM_CIBLE> echo "OK"

# Puis relancer le deploy
cd /root/vibe-vm-provisioner && make deploy
```

### Étape 4 — Accéder à VS Code

```
http://<IP_VM_CIBLE>:8080
```

Entrer le mot de passe défini lors du bootstrap (`CS_PASSWORD`).

---

## 🗂️ Structure du projet

```
vibe-vm-provisioner/
├── bootstrap.sh                  # Script de déploiement complet depuis le local
├── Makefile                      # make deploy / destroy / status / logs
├── ansible.cfg                   # Config Ansible (stdout yaml natif, pipelining)
├── .env.example                  # Template de variables (jamais commité)
├── .env                          # Secrets générés par bootstrap.sh (gitignore)
├── .gitignore                    # Exclut .env et inventory.ini
└── ansible/
    ├── inventory.ini.tpl         # Template → inventory.ini (via make)
    ├── inventory.ini             # Généré automatiquement (gitignore)
    ├── provision.yml             # Playbook principal
    └── files/
        └── settings.json         # Settings VS Code (JSON pur)
```

---

## 📦 Ce qui est installé sur la VM cible

| Composant | Détail |
|-----------|--------|
| Paquets système | `curl git unzip build-essential python3 ufw wget` |
| `nvm` | v0.39.7 — gestionnaire Node.js |
| Node.js | LTS (via nvm) |
| `@google/gemini-cli` | IA conversationnelle dans le terminal |
| `typescript` | Compilateur TypeScript global |
| `ruflo` | Orchestrateur multi-agents Claude |
| `agentic-flow` | Embeddings/routing pour Ruflo |
| `code-server` | VS Code natif dans le navigateur (port 8080) |
| Extension Python | `ms-python.python` |
| Extension ESLint | `dbaeumer.vscode-eslint` |
| Extension Prettier | `esbenp.prettier-vscode` |
| `ufw` | Pare-feu — ports 22 et 8080 ouverts uniquement |

---

## ⚡ Commandes Makefile

```bash
make deploy    # Provisionne la VM complète
make status    # Vérifie l'état de code-server (systemd)
make logs      # Affiche les logs en temps réel
make destroy   # Arrête code-server
make help      # Liste toutes les commandes
```

> Toutes ces commandes sont à lancer depuis la **VM Ansible**.

---

## 🤖 Utiliser les outils IA

### Gemini CLI

Dans le terminal intégré de VS Code (`Ctrl+\``) :

```bash
source ~/.bashrc    # si gemini n'est pas trouvé au 1er lancement
gemini              # mode chat interactif
gemini "explique ce fichier"
```

### Ruflo (multi-agents Claude)

```bash
# Vérifier l'état
ruflo doctor

# Initialiser dans ton workspace
cd ~/workspace
ruflo init --yes
ruflo swarm init --topology hierarchical --max-agents 4

# Spawner des agents
ruflo agent spawn -t coder
ruflo agent spawn -t tester
ruflo agent spawn -t reviewer

# Donner une tâche au swarm
ruflo task "crée une API REST Node.js avec tests"

# Surveiller les agents
ruflo swarm status
```

---

## 🔒 Sécurité

- `.env` et `ansible/inventory.ini` dans `.gitignore` — jamais committé
- Clés API saisies de façon masquée (mode secret) pendant le bootstrap
- `ufw` activé : seuls les ports 22 et 8080 sont accessibles
- Mot de passe code-server défini uniquement dans `.env`
- Token Git (si dans `WORKSPACE_REPO`) jamais loggué

---

## 🐛 Dépannage

**Vérifier code-server :**
```bash
ssh -i ~/.ssh/vibe-vm root@<IP_VM_CIBLE> 'systemctl status code-server@root'
```

**Voir les logs :**
```bash
make logs
# ou
ssh -i ~/.ssh/vibe-vm root@<IP_VM_CIBLE> 'journalctl -u code-server@root -f'
```

**Redémarrer code-server :**
```bash
ssh -i ~/.ssh/vibe-vm root@<IP_VM_CIBLE> 'systemctl restart code-server@root'
```

**`gemini` introuvable dans le terminal VS Code :**
```bash
source ~/.bashrc
gemini
```

**Erreur `community.general.yaml` callback removed :**
```bash
# Vérifier ansible.cfg — doit contenir :
stdout_callback = ansible.builtin.default
result_format   = yaml
# ET NON : stdout_callback = yaml
```

**Inventory vide / `no hosts matched` :**
```bash
cat ansible/inventory.ini   # doit contenir l'IP
make deploy                 # le regénère automatiquement
```

**`ssh-copy-id` échoue sur la VM cible :**
```bash
# Sur la VM cible manuellement :
echo "$(cat ~/.ssh/vibe-vm.pub)" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

---

## ♻️ Idempotence

Le playbook est entièrement rejouable sans casser l'existant :

```bash
cd /root/vibe-vm-provisioner
make deploy   # toujours sûr à relancer
```

---

## 📄 Licence

MIT