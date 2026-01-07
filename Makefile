TERRAFORM_DIR := terraform
SHELL := /bin/bash

.PHONY: help
help: ## Affiche l'aide
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

# Préparation
.PHONY: check
check: ## Vérifie les prérequis
	@command -v terraform &> /dev/null || (echo "✗ Terraform non installé" && exit 1)
	@[ -f ~/.ssh/id_rsa.pub ] || [ -f ~/.ssh/id_ed25519.pub ] || (echo "✗ Aucune clé SSH trouvée" && exit 1)
	@[ -n "$$OS_AUTH_URL" ] || echo "⚠ OS_AUTH_URL non défini"
	@[ -f $(TERRAFORM_DIR)/terraform.tfvars ] || echo "⚠ terraform.tfvars n'existe pas"
	@echo "✓ Vérifications OK"

.PHONY: init
init: ## Initialise Terraform
	cd $(TERRAFORM_DIR) && terraform init  -backend-config=backend.json;

.PHONY: setup
setup: ## Crée terraform.tfvars depuis l'exemple
	@[ ! -f $(TERRAFORM_DIR)/terraform.tfvars ] || (echo "terraform.tfvars existe déjà" && exit 1)
	@cp $(TERRAFORM_DIR)/terraform.tfvars.example $(TERRAFORM_DIR)/terraform.tfvars
	@echo "✓ terraform.tfvars créé"

# Connexions SSH
.PHONY: ssh-cp
ssh-cp: ## SSH au control-plane
	@IP=$$(cd $(TERRAFORM_DIR) && terraform output -raw control_plane_public_ip 2>/dev/null); \
	[ -n "$$IP" ] && ssh -o StrictHostKeyChecking=no ubuntu@$$IP || echo "Erreur: IP introuvable"

.PHONY: ssh-worker
ssh-worker: ## SSH au worker
	@IP=$$(cd $(TERRAFORM_DIR) && terraform output -raw worker_public_ip 2>/dev/null); \
	[ -n "$$IP" ] && ssh -o StrictHostKeyChecking=no ubuntu@$$IP || echo "Erreur: IP introuvable"

.PHONY: clean
clean: ## Nettoie les fichiers temporaires
	rm -rf $(TERRAFORM_DIR)/.terraform $(TERRAFORM_DIR)/tfplan $(TERRAFORM_DIR)/.terraform.lock.hcl
