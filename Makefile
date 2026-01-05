# =============================================================================
#                           MAKEFILE K8S-LAB
# =============================================================================
#
# CE FICHIER T'AIDE À :
# - Comprendre les commandes Terraform à exécuter
# - Éviter les erreurs courantes
# - Garder une trace de ce que tu fais
#
# UTILISATION :
#   make help        → Affiche toutes les commandes disponibles
#   make check       → Vérifie que tout est prêt AVANT de déployer
#   make plan        → Dry-run : montre ce qui SERAIT créé (sans rien créer)
#   make apply       → Crée l'infrastructure (après avoir vérifié avec plan)
#   make destroy     → Supprime TOUT (attention !)
#
# WORKFLOW RECOMMANDÉ (première fois) :
#   1. make check    → Vérifie les prérequis
#   2. make init     → Initialise Terraform
#   3. make plan     → Vérifie ce qui va être créé
#   4. make apply    → Crée l'infrastructure
#
# =============================================================================

# Variables
TERRAFORM_DIR := terraform
SHELL := /bin/bash

# Couleurs pour les messages
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

# =============================================================================
# AIDE
# =============================================================================

.PHONY: help
help: ## Affiche cette aide
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════════════╗"
	@echo "║                    COMMANDES DISPONIBLES                         ║"
	@echo "╚══════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "$(BLUE)PRÉPARATION :$(NC)"
	@echo "  make check          Vérifie que tout est prêt (terraform, clé SSH, etc.)"
	@echo "  make init           Initialise Terraform (télécharge les plugins)"
	@echo "  make setup          Configure terraform.tfvars interactivement"
	@echo ""
	@echo "$(BLUE)DÉPLOIEMENT :$(NC)"
	@echo "  make plan           🔍 DRY-RUN : montre ce qui serait créé (sans rien faire)"
	@echo "  make apply          🚀 Crée l'infrastructure (demande confirmation)"
	@echo "  make output         📋 Affiche les IPs et infos du cluster"
	@echo ""
	@echo "$(BLUE)GESTION :$(NC)"
	@echo "  make ssh-cp         🔑 Se connecte au control-plane en SSH"
	@echo "  make ssh-worker     🔑 Se connecte au worker en SSH"
	@echo "  make status         📊 Vérifie l'état des ressources"
	@echo ""
	@echo "$(RED)DESTRUCTION :$(NC)"
	@echo "  make destroy        ⚠️  SUPPRIME TOUT (demande confirmation)"
	@echo ""
	@echo "$(YELLOW)WORKFLOW RECOMMANDÉ (première fois) :$(NC)"
	@echo "  1. make check"
	@echo "  2. make init"
	@echo "  3. make plan"
	@echo "  4. make apply"
	@echo ""

# =============================================================================
# VÉRIFICATIONS
# =============================================================================

.PHONY: check
check: ## Vérifie que tout est prêt avant de déployer
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)                    VÉRIFICATION DES PRÉREQUIS                 $(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@# Vérifie Terraform
	@echo "$(YELLOW)1. Vérification de Terraform...$(NC)"
	@if command -v terraform &> /dev/null; then \
		echo "   $(GREEN)✓ Terraform installé$(NC): $$(terraform version -json 2>/dev/null | head -1 || terraform version | head -1)"; \
	else \
		echo "   $(RED)✗ Terraform non installé$(NC)"; \
		echo "     → Installe-le avec : brew install terraform"; \
		exit 1; \
	fi
	@echo ""
	@# Vérifie la clé SSH
	@echo "$(YELLOW)2. Vérification de la clé SSH...$(NC)"
	@if [ -f ~/.ssh/id_rsa.pub ]; then \
		echo "   $(GREEN)✓ Clé SSH trouvée$(NC): ~/.ssh/id_rsa.pub"; \
	elif [ -f ~/.ssh/id_ed25519.pub ]; then \
		echo "   $(GREEN)✓ Clé SSH trouvée$(NC): ~/.ssh/id_ed25519.pub"; \
		echo "   $(YELLOW)⚠ N'oublie pas de mettre à jour ssh_public_key_path dans terraform.tfvars$(NC)"; \
	else \
		echo "   $(RED)✗ Aucune clé SSH trouvée$(NC)"; \
		echo "     → Génère-en une avec : ssh-keygen -t ed25519 -C 'k8s-lab'"; \
		exit 1; \
	fi
	@echo ""
	@# Vérifie les variables d'environnement OpenStack
	@echo "$(YELLOW)3. Vérification des credentials OpenStack...$(NC)"
	@if [ -n "$$OS_AUTH_URL" ]; then \
		echo "   $(GREEN)✓ OS_AUTH_URL$(NC): $$OS_AUTH_URL"; \
	else \
		echo "   $(RED)✗ OS_AUTH_URL non défini$(NC)"; \
		echo "     → Télécharge openrc.sh depuis OVH Manager et exécute : source openrc.sh"; \
	fi
	@if [ -n "$$OS_USERNAME" ]; then \
		echo "   $(GREEN)✓ OS_USERNAME$(NC): $$OS_USERNAME"; \
	else \
		echo "   $(RED)✗ OS_USERNAME non défini$(NC)"; \
	fi
	@if [ -n "$$OS_PASSWORD" ]; then \
		echo "   $(GREEN)✓ OS_PASSWORD$(NC): (défini)"; \
	else \
		echo "   $(RED)✗ OS_PASSWORD non défini$(NC)"; \
	fi
	@if [ -n "$$OS_REGION_NAME" ]; then \
		echo "   $(GREEN)✓ OS_REGION_NAME$(NC): $$OS_REGION_NAME"; \
	else \
		echo "   $(YELLOW)⚠ OS_REGION_NAME non défini$(NC) (utilise la valeur par défaut)"; \
	fi
	@echo ""
	@# Vérifie terraform.tfvars
	@echo "$(YELLOW)4. Vérification de terraform.tfvars...$(NC)"
	@if [ -f $(TERRAFORM_DIR)/terraform.tfvars ]; then \
		echo "   $(GREEN)✓ terraform.tfvars existe$(NC)"; \
	else \
		echo "   $(RED)✗ terraform.tfvars n'existe pas$(NC)"; \
		echo "     → Copie l'exemple : cp $(TERRAFORM_DIR)/terraform.tfvars.example $(TERRAFORM_DIR)/terraform.tfvars"; \
		echo "     → Ou lance : make setup"; \
	fi
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""

# =============================================================================
# TERRAFORM - INITIALISATION
# =============================================================================

.PHONY: init
init: ## Initialise Terraform (télécharge les plugins)
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)                    INITIALISATION TERRAFORM                   $(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)Ce que ça fait :$(NC)"
	@echo "  - Télécharge le plugin OpenStack"
	@echo "  - Crée le répertoire .terraform/"
	@echo "  - Prépare Terraform pour les commandes suivantes"
	@echo ""
	@echo "$(YELLOW)C'est idempotent :$(NC) tu peux le relancer sans risque."
	@echo ""
	cd $(TERRAFORM_DIR) && terraform init
	@echo ""
	@echo "$(GREEN)✓ Initialisation terminée$(NC)"
	@echo "  → Prochaine étape : make plan"
	@echo ""

# =============================================================================
# TERRAFORM - PLAN (DRY-RUN)
# =============================================================================

.PHONY: plan
plan: ## DRY-RUN : montre ce qui serait créé sans rien faire
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)                    TERRAFORM PLAN (DRY-RUN)                   $(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)Ce que ça fait :$(NC)"
	@echo "  - Compare l'état actuel avec la configuration"
	@echo "  - Affiche ce qui SERAIT créé/modifié/supprimé"
	@echo "  - NE CRÉE RIEN"
	@echo ""
	@echo "$(GREEN)C'est sans danger :$(NC) aucune ressource n'est touchée."
	@echo ""
	cd $(TERRAFORM_DIR) && terraform plan
	@echo ""
	@echo "$(YELLOW)Si le plan te convient :$(NC) make apply"
	@echo ""

.PHONY: plan-save
plan-save: ## DRY-RUN et sauvegarde le plan dans un fichier
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)            TERRAFORM PLAN (DRY-RUN + SAUVEGARDE)              $(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)Ce que ça fait :$(NC)"
	@echo "  - Crée un fichier tfplan avec le plan exact"
	@echo "  - Ce fichier peut être appliqué avec 'terraform apply tfplan'"
	@echo "  - Garantit que ce qui est appliqué = ce qui a été planifié"
	@echo ""
	cd $(TERRAFORM_DIR) && terraform plan -out=tfplan
	@echo ""
	@echo "$(GREEN)✓ Plan sauvegardé dans terraform/tfplan$(NC)"
	@echo "  → Pour l'appliquer : cd terraform && terraform apply tfplan"
	@echo ""

# =============================================================================
# TERRAFORM - APPLY
# =============================================================================

.PHONY: apply
apply: ## Crée l'infrastructure (demande confirmation)
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)                    TERRAFORM APPLY                            $(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)Ce que ça fait :$(NC)"
	@echo "  - Crée les ressources définies dans les fichiers .tf"
	@echo "  - Sauvegarde l'état dans terraform.tfstate"
	@echo "  - Affiche les IPs et infos à la fin"
	@echo ""
	@echo "$(RED)⚠️  ATTENTION :$(NC)"
	@echo "  - Cette commande CRÉE des ressources payantes sur OVH"
	@echo "  - Terraform va te demander confirmation (tape 'yes')"
	@echo ""
	cd $(TERRAFORM_DIR) && terraform apply
	@echo ""
	@echo "$(GREEN)✓ Infrastructure créée !$(NC)"
	@echo "  → Attends 2-3 minutes que les VMs démarrent"
	@echo "  → Puis : make ssh-cp"
	@echo ""

.PHONY: apply-auto
apply-auto: ## Crée l'infrastructure SANS confirmation (⚠️ dangereux)
	@echo ""
	@echo "$(RED)⚠️  MODE AUTO-APPROVE : pas de confirmation !$(NC)"
	@echo ""
	cd $(TERRAFORM_DIR) && terraform apply -auto-approve
	@echo ""

# =============================================================================
# TERRAFORM - OUTPUT
# =============================================================================

.PHONY: output
output: ## Affiche les IPs et infos du cluster
	@echo ""
	cd $(TERRAFORM_DIR) && terraform output
	@echo ""

.PHONY: output-json
output-json: ## Affiche les outputs en JSON (pour scripts)
	@cd $(TERRAFORM_DIR) && terraform output -json

# =============================================================================
# CONNEXION SSH
# =============================================================================

.PHONY: ssh-cp
ssh-cp: ## Se connecte au control-plane en SSH
	@echo ""
	@echo "$(BLUE)Connexion au control-plane...$(NC)"
	@echo "$(YELLOW)Pour quitter : exit ou Ctrl+D$(NC)"
	@echo ""
	@IP=$$(cd $(TERRAFORM_DIR) && terraform output -raw control_plane_public_ip 2>/dev/null); \
	if [ -n "$$IP" ]; then \
		ssh -o StrictHostKeyChecking=no ubuntu@$$IP; \
	else \
		echo "$(RED)Erreur : impossible de récupérer l'IP.$(NC)"; \
		echo "As-tu lancé 'make apply' ?"; \
	fi

.PHONY: ssh-worker
ssh-worker: ## Se connecte au worker en SSH
	@echo ""
	@echo "$(BLUE)Connexion au worker...$(NC)"
	@echo "$(YELLOW)Pour quitter : exit ou Ctrl+D$(NC)"
	@echo ""
	@IP=$$(cd $(TERRAFORM_DIR) && terraform output -raw worker_public_ip 2>/dev/null); \
	if [ -n "$$IP" ]; then \
		ssh -o StrictHostKeyChecking=no ubuntu@$$IP; \
	else \
		echo "$(RED)Erreur : impossible de récupérer l'IP.$(NC)"; \
		echo "As-tu lancé 'make apply' ?"; \
	fi

# =============================================================================
# TERRAFORM - STATUS
# =============================================================================

.PHONY: status
status: ## Vérifie l'état des ressources
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)                    ÉTAT DES RESSOURCES                        $(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	cd $(TERRAFORM_DIR) && terraform state list
	@echo ""

.PHONY: show
show: ## Affiche les détails d'une ressource (usage: make show RES=nom_ressource)
	@if [ -z "$(RES)" ]; then \
		echo "$(RED)Usage: make show RES=nom_ressource$(NC)"; \
		echo "Exemple: make show RES=openstack_compute_instance_v2.control_plane"; \
		echo ""; \
		echo "Ressources disponibles:"; \
		cd $(TERRAFORM_DIR) && terraform state list; \
	else \
		cd $(TERRAFORM_DIR) && terraform state show $(RES); \
	fi

# =============================================================================
# TERRAFORM - DESTROY
# =============================================================================

.PHONY: destroy
destroy: ## ⚠️ SUPPRIME TOUT (demande confirmation)
	@echo ""
	@echo "$(RED)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(RED)                    ⚠️  DESTRUCTION ⚠️                          $(NC)"
	@echo "$(RED)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(RED)Cette commande va SUPPRIMER :$(NC)"
	@echo "  - Les 2 VMs (control-plane et worker)"
	@echo "  - Le réseau privé"
	@echo "  - Les IPs publiques"
	@echo "  - TOUT ce que Terraform a créé"
	@echo ""
	@echo "$(YELLOW)L'état Terraform (terraform.tfstate) sera conservé.$(NC)"
	@echo ""
	cd $(TERRAFORM_DIR) && terraform destroy
	@echo ""
	@echo "$(GREEN)✓ Ressources supprimées$(NC)"
	@echo ""

.PHONY: destroy-auto
destroy-auto: ## ⚠️ SUPPRIME TOUT SANS confirmation (très dangereux)
	@echo ""
	@echo "$(RED)⚠️  MODE AUTO-APPROVE : pas de confirmation !$(NC)"
	@echo ""
	cd $(TERRAFORM_DIR) && terraform destroy -auto-approve

# =============================================================================
# UTILITAIRES
# =============================================================================

.PHONY: setup
setup: ## Configure terraform.tfvars interactivement
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)                    CONFIGURATION                              $(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@if [ -f $(TERRAFORM_DIR)/terraform.tfvars ]; then \
		echo "$(YELLOW)terraform.tfvars existe déjà. Voulez-vous le remplacer ? (y/N)$(NC)"; \
		read -r response; \
		if [ "$$response" != "y" ] && [ "$$response" != "Y" ]; then \
			echo "Abandon."; \
			exit 0; \
		fi; \
	fi
	@cp $(TERRAFORM_DIR)/terraform.tfvars.example $(TERRAFORM_DIR)/terraform.tfvars
	@echo "$(GREEN)✓ terraform.tfvars créé$(NC)"
	@echo ""
	@echo "$(YELLOW)Édite ce fichier pour personnaliser :$(NC)"
	@echo "  vim $(TERRAFORM_DIR)/terraform.tfvars"
	@echo ""
	@echo "$(YELLOW)Ou ouvre-le dans ton éditeur :$(NC)"
	@echo "  code $(TERRAFORM_DIR)/terraform.tfvars"
	@echo ""

.PHONY: fmt
fmt: ## Formate les fichiers Terraform
	cd $(TERRAFORM_DIR) && terraform fmt

.PHONY: validate
validate: ## Valide la syntaxe des fichiers Terraform
	cd $(TERRAFORM_DIR) && terraform validate

.PHONY: clean
clean: ## Nettoie les fichiers temporaires (garde l'état !)
	@echo ""
	@echo "$(YELLOW)Nettoyage des fichiers temporaires...$(NC)"
	@echo "$(GREEN)Note : terraform.tfstate est conservé$(NC)"
	@echo ""
	rm -rf $(TERRAFORM_DIR)/.terraform
	rm -f $(TERRAFORM_DIR)/tfplan
	rm -f $(TERRAFORM_DIR)/.terraform.lock.hcl
	@echo "$(GREEN)✓ Nettoyage terminé$(NC)"
	@echo "  → Relance 'make init' avant d'utiliser Terraform"
	@echo ""

# =============================================================================
# BACKUP DE L'ÉTAT
# =============================================================================

.PHONY: backup
backup: ## Sauvegarde l'état Terraform
	@echo ""
	@BACKUP_FILE="terraform.tfstate.backup.$$(date +%Y%m%d_%H%M%S)"; \
	if [ -f $(TERRAFORM_DIR)/terraform.tfstate ]; then \
		cp $(TERRAFORM_DIR)/terraform.tfstate $(TERRAFORM_DIR)/$$BACKUP_FILE; \
		echo "$(GREEN)✓ État sauvegardé dans$(NC): terraform/$$BACKUP_FILE"; \
	else \
		echo "$(YELLOW)Aucun état à sauvegarder$(NC)"; \
	fi
	@echo ""

# =============================================================================
# INFO OPENSTACK
# =============================================================================

.PHONY: openstack-info
openstack-info: ## Affiche les infos OpenStack configurées
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)                    CONFIGURATION OPENSTACK                    $(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "OS_AUTH_URL     : $${OS_AUTH_URL:-$(RED)non défini$(NC)}"
	@echo "OS_TENANT_ID    : $${OS_TENANT_ID:-$(RED)non défini$(NC)}"
	@echo "OS_TENANT_NAME  : $${OS_TENANT_NAME:-$(RED)non défini$(NC)}"
	@echo "OS_USERNAME     : $${OS_USERNAME:-$(RED)non défini$(NC)}"
	@echo "OS_PASSWORD     : $${OS_PASSWORD:+$(GREEN)(défini)$(NC)}$${OS_PASSWORD:-$(RED)non défini$(NC)}"
	@echo "OS_REGION_NAME  : $${OS_REGION_NAME:-$(RED)non défini$(NC)}"
	@echo ""
	@echo "$(YELLOW)Pour configurer :$(NC)"
	@echo "  1. Va sur OVH Manager > Public Cloud > ton projet > Users & Roles"
	@echo "  2. Crée un utilisateur OpenStack (ou utilise un existant)"
	@echo "  3. Télécharge le fichier openrc.sh"
	@echo "  4. Exécute : source openrc.sh"
	@echo ""

