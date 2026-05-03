# =============================================================================
# Makefile — Point d'entrée unique du provisioning vibe-coding VM
# =============================================================================

SHELL := /bin/bash
ENV_FILE := .env

ifneq (,$(wildcard $(ENV_FILE)))
  include $(ENV_FILE)
  export $(shell sed 's/=.*//' $(ENV_FILE))
endif

CYAN  := \033[0;36m
GREEN := \033[0;32m
RED   := \033[0;31m
RESET := \033[0m

.DEFAULT_GOAL := help

.PHONY: deploy
deploy: _check-env _gen-inventory  ## Provisionne la VM complète (make deploy)
	@echo -e "$(CYAN)▶  Lancement du provisioning…$(RESET)"
	ansible-playbook \
		-i ansible/inventory.ini \
		ansible/provision.yml \
		--private-key "$(SSH_KEY_PATH)" \
		-u "$(TARGET_USER)" \
		-e "cs_password=$(CS_PASSWORD)" \
		-e "gemini_api_key=$(GEMINI_API_KEY)" \
		-e "workspace_repo=$(WORKSPACE_REPO)" \
		-e "target_user=$(TARGET_USER)" \
		$(ANSIBLE_EXTRA_ARGS)
	@echo -e "$(GREEN)✔  Provisioning terminé !$(RESET)"
	@echo -e "$(GREEN)🌐  Accès VS Code : http://$(TARGET_IP):8080$(RESET)"
	@echo -e "$(GREEN)🔑  Mot de passe  : voir CS_PASSWORD dans .env$(RESET)"

.PHONY: destroy
destroy: _check-env  ## Supprime code-server et nettoie la VM
	@echo -e "$(RED)⚠  Destruction en cours sur $(TARGET_IP)…$(RESET)"
	ssh -i "$(SSH_KEY_PATH)" -o StrictHostKeyChecking=no \
		"$(TARGET_USER)@$(TARGET_IP)" \
		'cd ~/code-server && docker compose down -v --remove-orphans || true'
	@echo -e "$(GREEN)✔  code-server arrêté.$(RESET)"

.PHONY: status
status: _check-env  ## Vérifie l'état des services sur la VM
	@echo -e "$(CYAN)▶  Statut sur $(TARGET_IP)…$(RESET)"
	ssh -i "$(SSH_KEY_PATH)" -o StrictHostKeyChecking=no \
		"$(TARGET_USER)@$(TARGET_IP)" \
		'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'

.PHONY: logs
logs: _check-env  ## Affiche les logs de code-server
	ssh -i "$(SSH_KEY_PATH)" -o StrictHostKeyChecking=no \
		"$(TARGET_USER)@$(TARGET_IP)" \
		'docker logs -f code-server'

.PHONY: _check-env
_check-env:
	@test -f $(ENV_FILE) || { echo -e "$(RED)✗  Fichier .env manquant.$(RESET)"; exit 1; }
	@for var in TARGET_IP TARGET_USER SSH_KEY_PATH GEMINI_API_KEY CS_PASSWORD WORKSPACE_REPO; do \
		eval val=\$${$$var}; \
		[ -n "$$val" ] || { echo -e "$(RED)✗  Variable $$var non définie dans .env$(RESET)"; exit 1; }; \
	done
	@echo -e "$(GREEN)✔  .env valide$(RESET)"

.PHONY: _gen-inventory
_gen-inventory:
	@mkdir -p ansible
	@echo "[vibe_vm]" > ansible/inventory.ini
	@echo "$(TARGET_IP) ansible_user=$(TARGET_USER) ansible_ssh_private_key_file=$(SSH_KEY_PATH) ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'" >> ansible/inventory.ini
	@echo "" >> ansible/inventory.ini
	@echo "[vibe_vm:vars]" >> ansible/inventory.ini
	@echo "ansible_python_interpreter=/usr/bin/python3" >> ansible/inventory.ini
	@echo -e "$(GREEN)✔  inventory.ini généré$(RESET)"
	@cat ansible/inventory.ini

.PHONY: help
help:  ## Affiche cette aide
	@echo -e "$(CYAN)Vibe-coding VM Provisioner$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-12s$(RESET) %s\n", $$1, $$2}'