TERRAFORM_DIR := terraform
SHELL := /bin/bash

.PHONY: help
help: ## Affiche l'aide
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

# Préparation
.PHONY: check
check: ## Vérifie les prérequis
	@command -v terraform &> /dev/null || (echo "✗ Terraform non installé" && exit 1)
	@[ -n "$$OS_AUTH_URL" ] || echo "⚠ OS_AUTH_URL non défini"
	@[ -f $(TERRAFORM_DIR)/terraform.tfvars ] || echo "⚠ terraform.tfvars n'existe pas"
	@echo "✓ Vérifications OK"

.PHONY: init
init: ## Initialise Terraform (utilise backend.yaml ou backend.json)
	@if [ -f $(TERRAFORM_DIR)/backend.yaml ]; then \
		cd $(TERRAFORM_DIR) && terraform init -backend-config=backend.yaml; \
	elif [ -f $(TERRAFORM_DIR)/backend.yml ]; then \
		cd $(TERRAFORM_DIR) && terraform init -backend-config=backend.yml; \
	else \
		cd $(TERRAFORM_DIR) && terraform init -backend-config=backend.json; \
	fi

.PHONY: setup
setup: ## Crée terraform.tfvars depuis l'exemple
	@[ ! -f $(TERRAFORM_DIR)/terraform.tfvars ] || (echo "terraform.tfvars existe déjà" && exit 1)
	@cp $(TERRAFORM_DIR)/terraform.tfvars.example $(TERRAFORM_DIR)/terraform.tfvars
	@echo "✓ terraform.tfvars créé"

.PHONY: cluster-info
cluster-info: ## Affiche les infos du cluster (IPs, commandes SSH)
	cd scripts/terraform/get-cluster-info && go run .

.PHONY: clean
clean: ## Nettoie les fichiers temporaires
	rm -rf $(TERRAFORM_DIR)/.terraform $(TERRAFORM_DIR)/tfplan $(TERRAFORM_DIR)/.terraform.lock.hcl
