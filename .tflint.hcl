# =============================================================================
# CONFIGURATION TFLINT - Linter pour Terraform
# =============================================================================
#
# CE QUE FAIT CE FICHIER :
# - Configure les règles de linting pour votre code Terraform
# - Active les plugins pour détecter les erreurs et les bonnes pratiques
#
# =============================================================================

config {
  call_module_type = "all"
  force            = false
}

# Plugin Terraform (inclus par défaut)
# Détecte les erreurs de syntaxe, les déclarations inutilisées, etc.
plugin "terraform" {
  enabled = true
  preset  = "all"  # Mode "all" pour des vérifications complètes
}

# Note : Il n'existe pas de plugin tflint spécifique pour OpenStack/OVH
# comme il en existe pour AWS, Azure ou GCP. Le plugin terraform de base
# suffit pour détecter les erreurs de syntaxe et les bonnes pratiques.
