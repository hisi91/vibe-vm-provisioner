# Vibe-coding VM - Provisioner automatique

Une seule commande depuis ta machine locale pour transformer une VM Debian/Ubuntu
vierge en environnement de vibe-coding complet : VS Code dans le navigateur +
Gemini CLI + Ruflo (orchestrateur multi-agents Claude).

```bash
./bootstrap.sh <IP_VM_ANSIBLE>
# -> http://<IP_VM_CIBLE>:8080
```

---

## Architecture

```
Ta machine locale
  |
  +-- ./bootstrap.sh 45.77.228.140
        |
        +-- Lit .env si present, sinon mode interactif
        +-- Demande de confirmation (recap des variables)
        +-- Ecrit le script remote dans /tmp/vibe_setup.sh
        +-- scp -> copie le script sur VM Ansible
        +-- ssh -> execute le script sur VM Ansible
              |
              +-- apt + ansible + community.general
              +-- git clone du repo
              +-- ssh-keygen -> ~/.ssh/vibe-vm
              +-- ssh-copy-id -> VM cible
              +-- test connexion SSH vers VM cible
              +-- ecriture du .env
              +-- make deploy
                    |
                    +-- SSH -> VM cible (ex: 45.63.67.185)
                          +-- paquets systeme
                          +-- nvm + Node LTS
                          +-- Gemini CLI
                          +-- TypeScript
                          +-- Ruflo + agentic-flow
                          +-- code-server natif (systemd)
                          +-- settings.json + extensions VS Code
                          +-- ufw (ports 22 + 8080)
                          +-- health check
```

---

## Prerequis

### Ta machine locale

| Outil | Verification |
|-------|-------------|
| ssh   | ssh -V      |
| scp   | scp -h      |
| Cle SSH vers VM Ansible | ls ~/.ssh/id_ed25519 |

### VM Ansible (machine de controle)

- Debian 12/13 ou Ubuntu 22/24
- Acces SSH root depuis ta machine locale
- Acces internet

### VM cible (machine provisionnee)

- Debian 12/13 ou Ubuntu 22/24
- Acces SSH root depuis la VM Ansible
- Ports ouverts : 22 + 8080
- 2 vCPU / 2 Go RAM minimum

---

## Deploiement de A a Z

### Etape 1 - Cloner ce repo sur ta machine locale

```bash
git clone https://github.com/hisi91/vibe-vm-provisioner.git
cd vibe-vm-provisioner
chmod +x bootstrap.sh
```

### Etape 2 - Lancer le bootstrap

```bash
# Minimal (user=root, cle=~/.ssh/id_ed25519)
./bootstrap.sh <IP_VM_ANSIBLE>

# Avec user custom
./bootstrap.sh <IP_VM_ANSIBLE> ubuntu

# Avec cle SSH specifique
./bootstrap.sh <IP_VM_ANSIBLE> root ~/.ssh/ma-cle
```

#### Cas A - Avec un fichier .env existant

Si un fichier `.env` est present dans le meme dossier que `bootstrap.sh`,
les variables sont chargees automatiquement sans aucune question :

```bash
# Creer le .env depuis le template
cp .env.example .env
nano .env

# Lancer - aucune question posee, juste une confirmation
./bootstrap.sh 45.77.228.140
```

```bash
TARGET_IP=45.63.67.xx
TARGET_USER=root
SSH_KEY_PATH=~/.ssh/vibe-vm
GEMINI_API_KEY=AI...
ANTHROPIC_API_KEY=sk-...
CS_PASSWORD=MonP@ss20XX
WORKSPACE_REPO=https://github.com/hisi91/vibe-vm-provisioner
```

#### Cas B - Sans fichier .env (mode interactif)

Le script pose les questions une par une :

```
=== Configuration de l'environnement ===

  IP de la VM cible
  -> ex: 45.63.67.185
  > _

  Utilisateur SSH sur la VM cible [defaut: root]
  > _

  Cle API Google Gemini
  -> https://aistudio.google.com/app/apikey
  > _

  Cle API Anthropic (Claude / Ruflo)
  -> https://console.anthropic.com/settings/keys
  > _

  Mot de passe pour acceder a VS Code
  -> min 8 caracteres
  > _

  URL HTTPS du repo Git a cloner dans ~/workspace
  -> Repo prive : https://TOKEN@github.com/user/repo.git
  > _
```

#### Cas C - .env partiel

Si le `.env` existe mais qu'il manque des variables, seules les variables
manquantes sont demandees interactivement.

### Etape 3 - Confirmation et lancement

Le script affiche un recapitulatif et demande confirmation :

```
=== Recapitulatif ===

  Source config      : .env (automatique)
  TARGET_IP          : 45.63.67.185
  TARGET_USER        : root
  GEMINI_API_KEY     : AIzaSyDl...
  ANTHROPIC_API_KEY  : sk-ant-a...
  CS_PASSWORD        : ********
  WORKSPACE_REPO     : https://github.com/hisi91/...

  Confirmer et lancer le bootstrap ? [O/n] :
```

### Etape 4 - Cas particulier : copie manuelle de la cle SSH

Si la VM cible n'accepte pas l'auth par mot de passe, le script affiche :

```
[!!]  Copie automatique impossible. Copie manuelle :

  ssh-copy-id -i ~/.ssh/vibe-vm.pub root@45.63.67.185
```

Connecte-toi sur la VM cible et colle la cle manuellement :

```bash
# Depuis ta machine locale
ssh root@<IP_VM_CIBLE>

# Sur la VM cible
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA... vibe-coding-provisioner" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit

# Tester depuis la VM Ansible
ssh -i ~/.ssh/vibe-vm root@<IP_VM_CIBLE> echo "OK"

# Relancer le deploy
cd /root/vibe-vm-provisioner && make deploy
```

### Etape 5 - Acces a VS Code

```
http://<IP_VM_CIBLE>:8080
```

Entrer le mot de passe defini dans `CS_PASSWORD`.

---

## Structure du projet

```
vibe-vm-provisioner/
|-- bootstrap.sh                  # Script de deploiement depuis le local
|-- Makefile                      # make deploy / destroy / status / logs
|-- ansible.cfg                   # stdout yaml natif, pipelining SSH
|-- .env.example                  # Template de variables
|-- .env                          # Secrets (dans .gitignore)
|-- .gitignore                    # Exclut .env et inventory.ini
+-- ansible/
    |-- inventory.ini.tpl         # Template -> inventory.ini (via make)
    |-- inventory.ini             # Genere automatiquement (gitignore)
    |-- provision.yml             # Playbook principal
    +-- files/
        +-- settings.json         # Settings VS Code (JSON pur)
```

---

## Variables du .env

| Variable | Description | Exemple |
|----------|-------------|---------|
| `TARGET_IP` | IP de la VM cible | `45.63.67.185` |
| `TARGET_USER` | Utilisateur SSH VM cible | `root` |
| `SSH_KEY_PATH` | Cle SSH generee par bootstrap | `~/.ssh/vibe-vm` |
| `GEMINI_API_KEY` | Cle Google Gemini | `AIza...` |
| `ANTHROPIC_API_KEY` | Cle Anthropic / Ruflo | `sk-ant-...` |
| `CS_PASSWORD` | Mot de passe VS Code | `MonP@ss2024` |
| `WORKSPACE_REPO` | Repo git a cloner | `https://github.com/...` |
| `ANSIBLE_EXTRA_ARGS` | Args Ansible optionnels | `-vvv` ou vide |

---

## Ce qui est installe sur la VM cible

| Composant | Detail |
|-----------|--------|
| Paquets systeme | curl git unzip build-essential python3 ufw wget |
| nvm v0.39.7 | Gestionnaire Node.js |
| Node.js LTS | Via nvm |
| @google/gemini-cli | IA conversationnelle dans le terminal |
| typescript | Compilateur TypeScript global |
| ruflo | Orchestrateur multi-agents Claude |
| agentic-flow | Embeddings/routing pour Ruflo |
| code-server | VS Code natif dans le navigateur (port 8080) |
| ms-python.python | Extension Python |
| dbaeumer.vscode-eslint | Extension ESLint |
| esbenp.prettier-vscode | Extension Prettier |
| ufw | Pare-feu - ports 22 et 8080 uniquement |

---

## Commandes Makefile

A lancer depuis la VM Ansible dans `/root/vibe-vm-provisioner` :

```bash
make deploy    # Provisionne la VM complete
make status    # Verifie l'etat de code-server (systemd)
make logs      # Affiche les logs en temps reel
make destroy   # Arrete code-server
make help      # Liste toutes les commandes
```

---

## Utiliser les outils IA dans VS Code

### Gemini CLI

Dans le terminal integre de VS Code (Ctrl+backtick) :

```bash
source ~/.bashrc    # si gemini n'est pas trouve au 1er lancement
gemini              # mode chat interactif
gemini "explique ce fichier"
```

### Ruflo (multi-agents Claude)

```bash
# Verifier l'etat
ruflo doctor

# Initialiser dans le workspace
cd ~/workspace
ruflo init --yes
ruflo swarm init --topology hierarchical --max-agents 4

# Spawner des agents
ruflo agent spawn -t coder
ruflo agent spawn -t tester
ruflo agent spawn -t reviewer

# Donner une tache
ruflo task "cree une API REST Node.js avec tests"

# Surveiller
ruflo swarm status
```

---

## Securite

- `.env` et `ansible/inventory.ini` dans `.gitignore` - jamais committe
- Cles API saisies en mode masque pendant le bootstrap
- `ufw` active : seuls les ports 22 et 8080 sont accessibles
- Mot de passe code-server uniquement dans `.env`
- Le script remote est cree dans `/tmp` et supprime apres usage

---

## Depannage

**Verifier code-server :**
```bash
ssh -i ~/.ssh/vibe-vm root@<IP_VM_CIBLE> systemctl status code-server@root
```

**Voir les logs :**
```bash
make logs
# ou
ssh -i ~/.ssh/vibe-vm root@<IP_VM_CIBLE> journalctl -u code-server@root -f
```

**Redemarrer code-server :**
```bash
ssh -i ~/.ssh/vibe-vm root@<IP_VM_CIBLE> systemctl restart code-server@root
```

**gemini introuvable dans le terminal VS Code :**
```bash
source ~/.bashrc
gemini
```

**make deploy ne se lance pas apres bootstrap :**
Le script remote est copie via scp puis execute via ssh.
Verifier que scp fonctionne depuis la VM Ansible vers la VM cible :
```bash
ssh -i ~/.ssh/vibe-vm root@<IP_VM_CIBLE> echo "OK"
```

**Erreur community.general.yaml callback removed :**
Verifier `ansible.cfg` - doit contenir :
```ini
stdout_callback = ansible.builtin.default
result_format   = yaml
```

**Inventory vide / no hosts matched :**
```bash
cat ansible/inventory.ini   # doit contenir l'IP
make deploy                 # le regenere automatiquement
```

---

## Idempotence

Le playbook est entierement rejouable :

```bash
cd /root/vibe-vm-provisioner
make deploy   # toujours sur a relancer
```

---

## Licence

MIT
