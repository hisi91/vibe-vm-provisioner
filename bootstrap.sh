#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — Prépare la machine Ansible et lance le provisioning complet
# Usage depuis ta machine locale :
#   chmod +x bootstrap.sh
#   ./bootstrap.sh <ANSIBLE_VM_IP> [ANSIBLE_VM_USER] [SSH_KEY_PATH]
#
# Exemples :
#   ./bootstrap.sh 45.77.228.140
#   ./bootstrap.sh 45.77.228.140 root
#   ./bootstrap.sh 45.77.228.140 root ~/.ssh/id_ed25519
# =============================================================================

set -euo pipefail

# ── Couleurs ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

log()    { echo -e "${CYAN}▶  $*${RESET}"; }
ok()     { echo -e "${GREEN}✔  $*${RESET}"; }
warn()   { echo -e "${YELLOW}⚠  $*${RESET}"; }
err()    { echo -e "${RED}✗  $*${RESET}"; exit 1; }
title()  { echo -e "\n${BOLD}${CYAN}$*${RESET}\n"; }
sep()    { echo -e "${CYAN}────────────────────────────────────────────────────${RESET}"; }

# ── Arguments ─────────────────────────────────────────────────────────────────
if [ $# -lt 1 ]; then
    echo -e "${RED}Usage : ./bootstrap.sh <ANSIBLE_VM_IP> [USER] [SSH_KEY]${RESET}"
    echo ""
    echo "  Exemples :"
    echo "    ./bootstrap.sh 45.77.228.140"
    echo "    ./bootstrap.sh 45.77.228.140 root"
    echo "    ./bootstrap.sh 45.77.228.140 root ~/.ssh/id_ed25519"
    exit 1
fi

ANSIBLE_VM_IP="$1"
ANSIBLE_VM_USER="${2:-root}"
ANSIBLE_VM_SSH_KEY="${3:-~/.ssh/id_ed25519}"
REPO_URL="${REPO_URL:-https://github.com/hisi91/vibe-vm-provisioner.git}"
REPO_DIR="/root/vibe-vm-provisioner"
TARGET_SSH_KEY_NAME="vibe-vm"
SSH_KEY_EXPANDED="${ANSIBLE_VM_SSH_KEY/#\~/$HOME}"

# ── Bannière ──────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║        VIBE-CODING VM — Bootstrap                ║"
echo "  ║   Provisioning automatique depuis le local       ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo "  VM Ansible    : $ANSIBLE_VM_USER@$ANSIBLE_VM_IP"
echo "  Clé SSH local : $ANSIBLE_VM_SSH_KEY"
echo "  Repo          : $REPO_URL"
sep

# ── Collecte interactive du .env ──────────────────────────────────────────────
title "📝 Configuration de l'environnement"
echo "  Renseigne les informations ci-dessous."
echo "  (Appuie sur Entrée pour garder la valeur par défaut si affichée)"
echo ""

prompt_required() {
    local var_name="$1"
    local label="$2"
    local hint="$3"
    local value=""
    while [ -z "$value" ]; do
        echo -e "  ${BOLD}${label}${RESET}"
        [ -n "$hint" ] && echo -e "  ${YELLOW}→ $hint${RESET}"
        read -rp "  > " value
        [ -z "$value" ] && echo -e "  ${RED}Valeur obligatoire.${RESET}"
    done
    eval "$var_name=\"$value\""
}

prompt_default() {
    local var_name="$1"
    local label="$2"
    local default="$3"
    local hint="$4"
    echo -e "  ${BOLD}${label}${RESET} [défaut: ${GREEN}${default}${RESET}]"
    [ -n "$hint" ] && echo -e "  ${YELLOW}→ $hint${RESET}"
    read -rp "  > " value
    eval "$var_name=\"${value:-$default}\""
}

prompt_secret() {
    local var_name="$1"
    local label="$2"
    local hint="$3"
    local value=""
    while [ -z "$value" ]; do
        echo -e "  ${BOLD}${label}${RESET}"
        [ -n "$hint" ] && echo -e "  ${YELLOW}→ $hint${RESET}"
        read -rsp "  > " value
        echo ""
        [ -z "$value" ] && echo -e "  ${RED}Valeur obligatoire.${RESET}"
    done
    eval "$var_name=\"$value\""
}

sep
echo ""

# VM cible
prompt_required TARGET_IP \
    "IP de la VM cible (celle qui recevra VS Code)" \
    "ex: 216.128.156.17"

prompt_default TARGET_USER \
    "Utilisateur SSH sur la VM cible" \
    "root" \
    "généralement 'root' sur Vultr/Hetzner, 'ubuntu' sur AWS"

# Clés API
echo ""
sep
echo -e "  ${BOLD}Clés API${RESET}"
sep
echo ""

prompt_secret GEMINI_API_KEY \
    "Clé API Google Gemini" \
    "https://aistudio.google.com/app/apikey"

prompt_secret ANTHROPIC_API_KEY \
    "Clé API Anthropic (Claude / Ruflo)" \
    "https://console.anthropic.com/settings/keys"

# code-server
echo ""
sep
echo -e "  ${BOLD}VS Code (code-server)${RESET}"
sep
echo ""

prompt_secret CS_PASSWORD \
    "Mot de passe pour accéder à VS Code" \
    "min 8 caractères, ex: MonP@ss2024"

# Workspace
echo ""
sep
echo -e "  ${BOLD}Workspace Git${RESET}"
sep
echo ""

prompt_default WORKSPACE_REPO \
    "URL HTTPS du repo Git à cloner dans ~/workspace" \
    "https://github.com/hisi91/vibe-vm-provisioner.git" \
    "Repo privé : https://ghp_TOKEN@github.com/user/repo.git"

# Résumé
echo ""
sep
title "📋 Récapitulatif"
echo "  TARGET_IP        : $TARGET_IP"
echo "  TARGET_USER      : $TARGET_USER"
echo "  GEMINI_API_KEY   : ${GEMINI_API_KEY:0:8}..."
echo "  ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:0:8}..."
echo "  CS_PASSWORD      : ********"
echo "  WORKSPACE_REPO   : $WORKSPACE_REPO"
sep
echo ""
read -rp "  Confirmer et lancer le bootstrap ? [O/n] : " CONFIRM
[[ "${CONFIRM:-O}" =~ ^[Nn]$ ]] && { echo "Annulé."; exit 0; }

# ── Vérifications locales ─────────────────────────────────────────────────────
title "🔍 Vérifications locales"

command -v ssh >/dev/null || err "ssh non trouvé"
command -v scp >/dev/null || err "scp non trouvé"
[ -f "$SSH_KEY_EXPANDED" ] || err "Clé SSH locale introuvable : $SSH_KEY_EXPANDED"
ok "Prérequis locaux OK"

# ── Test connexion VM Ansible ─────────────────────────────────────────────────
log "Test de connexion vers VM Ansible ($ANSIBLE_VM_IP)..."
ssh -i "$SSH_KEY_EXPANDED" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "$ANSIBLE_VM_USER@$ANSIBLE_VM_IP" \
    "echo connected" >/dev/null || err "Impossible de se connecter à $ANSIBLE_VM_IP"
ok "Connexion SSH vers VM Ansible OK"

# ── Exécution remote sur la VM Ansible ───────────────────────────────────────
title "🚀 Setup de la VM Ansible ($ANSIBLE_VM_IP)"

ssh -i "$SSH_KEY_EXPANDED" \
    -o StrictHostKeyChecking=no \
    "$ANSIBLE_VM_USER@$ANSIBLE_VM_IP" \
    bash -s -- \
        "$REPO_URL" \
        "$REPO_DIR" \
        "$TARGET_SSH_KEY_NAME" \
        "$TARGET_IP" \
        "$TARGET_USER" \
        "$GEMINI_API_KEY" \
        "$ANTHROPIC_API_KEY" \
        "$CS_PASSWORD" \
        "$WORKSPACE_REPO" \
<< 'REMOTE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

REPO_URL="$1"
REPO_DIR="$2"
KEY_NAME="$3"
TARGET_IP="$4"
TARGET_USER="$5"
GEMINI_API_KEY="$6"
ANTHROPIC_API_KEY="$7"
CS_PASSWORD="$8"
WORKSPACE_REPO="$9"
KEY_PATH="$HOME/.ssh/$KEY_NAME"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'
log() { echo -e "${CYAN}▶  $*${RESET}"; }
ok()  { echo -e "${GREEN}✔  $*${RESET}"; }
err() { echo -e "${RED}✗  $*${RESET}"; exit 1; }

# ── 1. Paquets système ────────────────────────────────────────────────────────
log "Installation des paquets système..."
apt-get update -qq
apt-get install -y -qq \
    python3 python3-pip pipx \
    git curl wget unzip \
    sshpass gettext-base \
    2>/dev/null
ok "Paquets installés"

# ── 2. Ansible ────────────────────────────────────────────────────────────────
log "Installation d'Ansible..."
export PATH="$HOME/.local/bin:$PATH"
if ! command -v ansible >/dev/null 2>&1; then
    apt install ansible 2>/dev/null \
        || pip install ansible --break-system-packages -q
fi
grep -q '.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
ok "Ansible : $(ansible --version | head -1)"

# ── 3. Collection community.general ──────────────────────────────────────────
log "Installation community.general..."
ansible-galaxy collection install community.general --force-with-deps
ok "Collection installée"

# ── 4. Clone du repo ──────────────────────────────────────────────────────────
log "Clone du repo..."
if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" pull --rebase
    ok "Repo mis à jour"
else
    git clone "$REPO_URL" "$REPO_DIR"
    ok "Repo cloné : $REPO_DIR"
fi

# ── 5. Génération clé SSH ─────────────────────────────────────────────────────
log "Génération de la clé SSH $KEY_PATH..."
mkdir -p ~/.ssh && chmod 700 ~/.ssh
if [ ! -f "$KEY_PATH" ]; then
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "vibe-coding-provisioner"
    ok "Clé générée"
else
    ok "Clé déjà existante"
fi

# ── 6. Copie clé sur VM cible ─────────────────────────────────────────────────
log "Copie de la clé publique sur la VM cible ($TARGET_IP)..."
ssh-copy-id \
    -i "${KEY_PATH}.pub" \
    -o StrictHostKeyChecking=no \
    "${TARGET_USER}@${TARGET_IP}" 2>/dev/null \
&& ok "Clé copiée sur $TARGET_IP" \
|| {
    echo ""
    echo "  ⚠  Copie automatique impossible."
    echo "  Copie manuelle de cette clé sur $TARGET_IP :"
    echo ""
    cat "${KEY_PATH}.pub"
    echo ""
}

# ── 7. Écriture du .env ───────────────────────────────────────────────────────
log "Écriture du fichier .env..."
cat > "$REPO_DIR/.env" << ENV
# Généré automatiquement par bootstrap.sh
TARGET_IP=$TARGET_IP
TARGET_USER=$TARGET_USER
SSH_KEY_PATH=$KEY_PATH
GEMINI_API_KEY=$GEMINI_API_KEY
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
CS_PASSWORD=$CS_PASSWORD
WORKSPACE_REPO=$WORKSPACE_REPO
ANSIBLE_EXTRA_ARGS=
ENV
chmod 600 "$REPO_DIR/.env"
ok ".env écrit dans $REPO_DIR/.env"

# ── 8. Lancement du provisioning ──────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}  Bootstrap terminé ! Lancement de make deploy...  ${RESET}"
echo -e "${GREEN}════════════════════════════════════════════════════${RESET}"
echo ""

cd "$REPO_DIR"
export PATH="$HOME/.local/bin:$PATH"
make deploy

REMOTE_SCRIPT

# ── Résumé final ──────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║           ✔  PROVISIONING TERMINÉ !              ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo "  🌐  VS Code  : http://$TARGET_IP:8080"
echo "  🔑  Password : (CS_PASSWORD dans votre .env)"
echo "  🤖  Gemini   : taper 'gemini' dans le terminal VS Code"
echo "  🦾  Ruflo    : taper 'ruflo doctor' dans le terminal VS Code"
echo ""