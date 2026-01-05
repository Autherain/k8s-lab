# =============================================================================
# CONFIGURATION TFLINT - Linter pour Terraform
# =============================================================================
#
# CE QUE FAIT CE FICHIER :
# - Configure les règles de linting pour votre code Terraform
# - Active les plugins pour détecter les erreurs et les bonnes pratiques
#
# =============================================================================

# Plugin Terraform (inclus par défaut)
# Détecte les erreurs de syntaxe, les déclarations inutilisées, etc.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Note : Il n'existe pas de plugin tflint spécifique pour OpenStack/OVH
# comme il en existe pour AWS, Azure ou GCP. Le plugin terraform de base
# suffit pour détecter les erreurs de syntaxe et les bonnes pratiques.

