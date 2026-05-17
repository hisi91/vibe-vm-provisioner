#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — Prepare la machine Ansible et lance le provisioning complet
# Usage :
#   ./bootstrap.sh <ANSIBLE_VM_IP> [USER] [SSH_KEY]
#   ./bootstrap.sh 45.77.228.140
#   ./bootstrap.sh 45.77.228.140 root ~/.ssh/id_ed25519
# Si .env existe dans le meme dossier, les variables sont chargees auto.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

log()   { echo -e "${CYAN}[>>]  $*${RESET}"; }
ok()    { echo -e "${GREEN}[OK]  $*${RESET}"; }
warn()  { echo -e "${YELLOW}[!!]  $*${RESET}"; }
err()   { echo -e "${RED}[XX]  $*${RESET}"; exit 1; }
title() { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}\n"; }
sep()   { echo -e "${CYAN}----------------------------------------------------${RESET}"; }

# ── Arguments ─────────────────────────────────────────────────────────────────
if [ $# -lt 1 ]; then
    echo -e "${RED}Usage : $0 <ANSIBLE_VM_IP> [USER] [SSH_KEY]${RESET}"
    echo ""
    echo "  Exemples :"
    echo "    $0 45.77.228.140"
    echo "    $0 45.77.228.140 root"
    echo "    $0 45.77.228.140 root ~/.ssh/id_ed25519"
    exit 1
fi

ANSIBLE_VM_IP="$1"
ANSIBLE_VM_USER="${2:-root}"
ANSIBLE_VM_SSH_KEY="${3:-~/.ssh/id_ed25519}"
REPO_URL="${REPO_URL:-https://github.com/hisi91/vibe-vm-provisioner.git}"
REPO_DIR="/root/vibe-vm-provisioner"
TARGET_SSH_KEY_NAME="vibe-vm"
SSH_KEY_EXPANDED="${ANSIBLE_VM_SSH_KEY/#\~/$HOME}"
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/.env"

# ── Banniere ──────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
echo "  +==================================================+"
echo "  |       VIBE-CODING VM - Bootstrap                |"
echo "  |  Provisioning automatique depuis le local       |"
echo "  +==================================================+"
echo -e "${RESET}"
echo "  VM Ansible    : ${ANSIBLE_VM_USER}@${ANSIBLE_VM_IP}"
echo "  Cle SSH local : ${ANSIBLE_VM_SSH_KEY}"
echo "  Repo          : ${REPO_URL}"
sep

# ── Chargement .env ou mode interactif ────────────────────────────────────────

# Initialiser les variables vides
TARGET_IP=""
TARGET_USER=""
GEMINI_API_KEY=""
ANTHROPIC_API_KEY=""
CS_PASSWORD=""
WORKSPACE_REPO=""

if [ -f "$ENV_FILE" ]; then
    echo ""
    ok "Fichier .env trouve - chargement automatique"
    echo ""

    # Lecture ligne par ligne du .env
    while IFS= read -r line || [ -n "$line" ]; do
        # Ignorer commentaires et lignes vides
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        # Extraire cle=valeur
        if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            # Supprimer guillemets
            val="${val%\"}" ; val="${val#\"}"
            val="${val%"'"}" ; val="${val#"'"}"
            # Supprimer commentaires inline
            val="${val%%#*}"
            # Trim espaces
            val="${val#"${val%%[! ]*}"}"
            val="${val%"${val##*[! ]}"}"
            export "$key=$val"
            # Capturer les variables dont on a besoin
            case "$key" in
                TARGET_IP)         TARGET_IP="$val" ;;
                TARGET_USER)       TARGET_USER="$val" ;;
                GEMINI_API_KEY)    GEMINI_API_KEY="$val" ;;
                ANTHROPIC_API_KEY) ANTHROPIC_API_KEY="$val" ;;
                CS_PASSWORD)       CS_PASSWORD="$val" ;;
                WORKSPACE_REPO)    WORKSPACE_REPO="$val" ;;
            esac
        fi
    done < "$ENV_FILE"

    # Verifier les variables manquantes
    MISSING=()
    [ -z "$TARGET_IP" ]         && MISSING+=("TARGET_IP")
    [ -z "$TARGET_USER" ]       && MISSING+=("TARGET_USER")
    [ -z "$GEMINI_API_KEY" ]    && MISSING+=("GEMINI_API_KEY")
    [ -z "$ANTHROPIC_API_KEY" ] && MISSING+=("ANTHROPIC_API_KEY")
    [ -z "$CS_PASSWORD" ]       && MISSING+=("CS_PASSWORD")
    [ -z "$WORKSPACE_REPO" ]    && MISSING+=("WORKSPACE_REPO")

    if [ ${#MISSING[@]} -gt 0 ]; then
        warn "Variables manquantes dans .env : ${MISSING[*]}"
        warn "Ces variables vont etre demandees interactivement."
        INTERACTIVE_MODE=true
    else
        ok "Toutes les variables chargees depuis .env"
        INTERACTIVE_MODE=false
    fi
else
    warn "Aucun fichier .env trouve - mode interactif"
    INTERACTIVE_MODE=true
fi

# ── Fonctions de prompt ───────────────────────────────────────────────────────
ask_required() {
    local varname="$1"
    local label="$2"
    local hint="$3"
    local current
    current="$(eval echo \${$varname:-})"
    [ -n "$current" ] && return

    local val=""
    while [ -z "$val" ]; do
        echo -e "  ${BOLD}${label}${RESET}"
        [ -n "$hint" ] && echo -e "  ${YELLOW}-> ${hint}${RESET}"
        read -rp "  > " val
        [ -z "$val" ] && echo -e "  ${RED}Valeur obligatoire.${RESET}"
    done
    eval "$varname=\"$val\""
}

ask_default() {
    local varname="$1"
    local label="$2"
    local default="$3"
    local hint="$4"
    local current
    current="$(eval echo \${$varname:-})"
    [ -n "$current" ] && return

    echo -e "  ${BOLD}${label}${RESET} [defaut: ${GREEN}${default}${RESET}]"
    [ -n "$hint" ] && echo -e "  ${YELLOW}-> ${hint}${RESET}"
    read -rp "  > " val
    eval "$varname=\"${val:-$default}\""
}

ask_secret() {
    local varname="$1"
    local label="$2"
    local hint="$3"
    local current
    current="$(eval echo \${$varname:-})"
    [ -n "$current" ] && return

    local val=""
    while [ -z "$val" ]; do
        echo -e "  ${BOLD}${label}${RESET}"
        [ -n "$hint" ] && echo -e "  ${YELLOW}-> ${hint}${RESET}"
        read -rsp "  > " val
        echo ""
        [ -z "$val" ] && echo -e "  ${RED}Valeur obligatoire.${RESET}"
    done
    eval "$varname=\"$val\""
}

# ── Collecte interactive (variables manquantes seulement) ─────────────────────
if [ "$INTERACTIVE_MODE" = true ]; then
    title "Configuration de l'environnement"
    echo "  Renseigne les informations ci-dessous."
    [ -f "$ENV_FILE" ] && echo "  (Seules les variables manquantes sont demandees)"
    echo ""

    sep
    echo -e "  ${BOLD}VM cible${RESET}"
    sep
    echo ""

    ask_required TARGET_IP \
        "IP de la VM cible (VS Code sera installe ici)" \
        "ex: 216.128.156.17"

    ask_default TARGET_USER \
        "Utilisateur SSH sur la VM cible" \
        "root" \
        "root sur Vultr/Hetzner, ubuntu sur AWS"

    echo ""
    sep
    echo -e "  ${BOLD}Cles API${RESET}"
    sep
    echo ""

    ask_secret GEMINI_API_KEY \
        "Cle API Google Gemini" \
        "https://aistudio.google.com/app/apikey"

    ask_secret ANTHROPIC_API_KEY \
        "Cle API Anthropic (Claude / Ruflo)" \
        "https://console.anthropic.com/settings/keys"

    echo ""
    sep
    echo -e "  ${BOLD}VS Code (code-server)${RESET}"
    sep
    echo ""

    ask_secret CS_PASSWORD \
        "Mot de passe pour acceder a VS Code" \
        "min 8 caracteres"

    echo ""
    sep
    echo -e "  ${BOLD}Workspace Git${RESET}"
    sep
    echo ""

    ask_default WORKSPACE_REPO \
        "URL HTTPS du repo Git a cloner dans ~/workspace" \
        "https://github.com/hisi91/vibe-vm-provisioner.git" \
        "Repo prive : https://TOKEN@github.com/user/repo.git"
fi

# Valeur par defaut TARGET_USER
TARGET_USER="${TARGET_USER:-root}"

# ── Recapitulatif ─────────────────────────────────────────────────────────────
echo ""
sep
title "Recapitulatif"
echo "  Source config      : $([ -f "$ENV_FILE" ] && echo ".env (automatique)" || echo "interactif")"
echo "  TARGET_IP          : ${TARGET_IP}"
echo "  TARGET_USER        : ${TARGET_USER}"
echo "  GEMINI_API_KEY     : ${GEMINI_API_KEY:0:8}..."
echo "  ANTHROPIC_API_KEY  : ${ANTHROPIC_API_KEY:0:8}..."
echo "  CS_PASSWORD        : ********"
echo "  WORKSPACE_REPO     : ${WORKSPACE_REPO}"
sep
echo ""
read -rp "  Confirmer et lancer le bootstrap ? [O/n] : " CONFIRM
[[ "${CONFIRM:-O}" =~ ^[Nn]$ ]] && { echo "Annule."; exit 0; }

# ── Verifications locales ─────────────────────────────────────────────────────
title "Verifications locales"
command -v ssh >/dev/null || err "ssh non trouve"
command -v scp >/dev/null || err "scp non trouve"
[ -f "$SSH_KEY_EXPANDED" ] || err "Cle SSH locale introuvable : ${SSH_KEY_EXPANDED}"
ok "Prerequis locaux OK"

# ── Test connexion VM Ansible ─────────────────────────────────────────────────
log "Test connexion vers VM Ansible (${ANSIBLE_VM_IP})..."
ssh -i "$SSH_KEY_EXPANDED" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "${ANSIBLE_VM_USER}@${ANSIBLE_VM_IP}" \
    "echo connected" >/dev/null \
    || err "Impossible de se connecter a ${ANSIBLE_VM_IP}"
ok "Connexion SSH vers VM Ansible OK"

# ── Execution remote sur la VM Ansible ───────────────────────────────────────
title "Setup de la VM Ansible (${ANSIBLE_VM_IP})"

# Ecrire le script remote dans un fichier temporaire local
REMOTE_SCRIPT_FILE=$(mktemp /tmp/vibe_remote_XXXXXX.sh)

cat > "$REMOTE_SCRIPT_FILE" << REMOTE_SCRIPT_EOF
#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL}"
REPO_DIR="${REPO_DIR}"
KEY_NAME="${TARGET_SSH_KEY_NAME}"
TARGET_IP="${TARGET_IP}"
TARGET_USER="${TARGET_USER}"
GEMINI_API_KEY="${GEMINI_API_KEY}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"
CS_PASSWORD="${CS_PASSWORD}"
WORKSPACE_REPO="${WORKSPACE_REPO}"
KEY_PATH="\$HOME/.ssh/\$KEY_NAME"

RED="[0;31m"; GREEN="[0;32m"; CYAN="[0;36m"; YELLOW="[1;33m"; RESET="[0m"
log()  { echo -e "\${CYAN}[>>]  \$*\${RESET}"; }
ok()   { echo -e "\${GREEN}[OK]  \$*\${RESET}"; }
warn() { echo -e "\${YELLOW}[!!]  \$*\${RESET}"; }
err()  { echo -e "\${RED}[XX]  \$*\${RESET}"; exit 1; }

# 1. Paquets systeme
log "Installation des paquets systeme..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3 python3-pip pipx git curl wget unzip sshpass gettext-base
ok "Paquets installes"

# 2. Ansible
log "Installation d'Ansible..."
export PATH="\$HOME/.local/bin:\$PATH"
if ! command -v ansible >/dev/null 2>&1; then
    apt-get install -y -qq ansible 2>/dev/null \
        || pip install ansible --break-system-packages -q
fi
grep -q ".local/bin" ~/.bashrc || echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.bashrc
ok "Ansible : \$(ansible --version | head -1)"

# 3. Collection community.general
log "Installation community.general..."
ansible-galaxy collection install community.general --force-with-deps
ok "Collection installee"

# 4. Clone du repo
log "Clone du repo..."
if [ -d "\$REPO_DIR/.git" ]; then
    git -C "\$REPO_DIR" pull --rebase
    ok "Repo mis a jour"
else
    git clone "\$REPO_URL" "\$REPO_DIR"
    ok "Repo clone : \$REPO_DIR"
fi

# 5. Generation cle SSH
log "Generation de la cle SSH..."
mkdir -p ~/.ssh && chmod 700 ~/.ssh
if [ ! -f "\$KEY_PATH" ]; then
    ssh-keygen -t ed25519 -f "\$KEY_PATH" -N "" -C "vibe-coding-provisioner"
    ok "Cle generee : \$KEY_PATH"
else
    ok "Cle deja existante : \$KEY_PATH"
fi

# 6. Copie cle sur VM cible
log "Copie de la cle sur la VM cible (\$TARGET_IP)..."
if ssh-copy-id -i "\${KEY_PATH}.pub" "\${TARGET_USER}@\${TARGET_IP}"; then
    ok "Cle copiee sur \$TARGET_IP"
else
    warn "Copie automatique impossible. Copie manuelle :"
    echo ""
    echo "  ssh-copy-id -i \${KEY_PATH}.pub \${TARGET_USER}@\${TARGET_IP}"
    echo ""
    warn "Puis relance : cd \$REPO_DIR && make deploy"
    exit 1
fi

# Test connexion SSH
log "Test connexion SSH vers VM cible (\$TARGET_IP)..."
ssh -i "\$KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    "\${TARGET_USER}@\${TARGET_IP}" "echo OK" >/dev/null \
    && ok "Connexion SSH vers VM cible OK" \
    || err "Connexion SSH echouee vers \$TARGET_IP"

# 7. Ecriture du .env
log "Ecriture du fichier .env..."
cat > "\$REPO_DIR/.env" << ENVEOF
TARGET_IP=\$TARGET_IP
TARGET_USER=\$TARGET_USER
SSH_KEY_PATH=\$KEY_PATH
GEMINI_API_KEY=\$GEMINI_API_KEY
ANTHROPIC_API_KEY=\$ANTHROPIC_API_KEY
CS_PASSWORD=\$CS_PASSWORD
WORKSPACE_REPO=\$WORKSPACE_REPO
ANSIBLE_EXTRA_ARGS=
ENVEOF
chmod 600 "\$REPO_DIR/.env"
ok ".env ecrit"

# 8. Lancement du provisioning
echo ""
echo -e "\${GREEN}----------------------------------------------------\${RESET}"
echo -e "\${GREEN}  Lancement de make deploy...                       \${RESET}"
echo -e "\${GREEN}----------------------------------------------------\${RESET}"
echo ""
cd "\$REPO_DIR"
export PATH="\$HOME/.local/bin:\$PATH"
make deploy
REMOTE_SCRIPT_EOF

# Copier le script sur la VM Ansible et l'executer
log "Copie du script sur la VM Ansible..."
scp -i "$SSH_KEY_EXPANDED"     -o StrictHostKeyChecking=no     "$REMOTE_SCRIPT_FILE"     "${ANSIBLE_VM_USER}@${ANSIBLE_VM_IP}:/tmp/vibe_setup.sh"

rm -f "$REMOTE_SCRIPT_FILE"
ok "Script copie"

log "Execution du script sur la VM Ansible..."
ssh -i "$SSH_KEY_EXPANDED"     -o StrictHostKeyChecking=no     "${ANSIBLE_VM_USER}@${ANSIBLE_VM_IP}"     "chmod +x /tmp/vibe_setup.sh && bash /tmp/vibe_setup.sh"


# ── Resume final ──────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}"
echo "  +==================================================+"
echo "  |          PROVISIONING TERMINE avec succes !     |"
echo "  +==================================================+"
echo -e "${RESET}"
echo "  VS Code   : http://${TARGET_IP}:8080"
echo "  Password  : (CS_PASSWORD dans ton .env)"
echo "  Gemini    : taper  gemini  dans le terminal VS Code"
echo "  Ruflo     : taper  ruflo doctor  dans le terminal"
echo ""
