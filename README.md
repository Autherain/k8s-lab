# k8s-lab
A project designed to help me learn how to setup my k8s cluster through kubeadm

## Utilisation de TFLint

TFLint est un linter pour Terraform qui permet de détecter les erreurs et les bonnes pratiques dans votre code.

### Configuration

Un fichier `.tflint.hcl` a été créé dans le répertoire `terraform/` avec la configuration de base.

### Commandes utiles

1. **Initialiser les plugins** (première fois uniquement) :
   ```bash
   cd terraform
   tflint --init
   ```

2. **Lancer l'analyse** :
   ```bash
   cd terraform
   tflint
   ```

3. **Analyser un fichier spécifique** :
   ```bash
   cd terraform
   tflint instances.tf
   ```

4. **Format de sortie JSON** :
   ```bash
   tflint -f json
   ```

5. **Corriger automatiquement les problèmes** (si possible) :
   ```bash
   tflint --fix
   ```

### Options utiles

- `--format=json` : Sortie au format JSON (utile pour l'intégration CI/CD)
- `--format=compact` : Format compact
- `--recursive` : Analyser récursivement tous les sous-répertoires
- `--enable-rule=RULE_NAME` : Activer une règle spécifique
- `--disable-rule=RULE_NAME` : Désactiver une règle spécifique

### Résolution des problèmes de plugins

Si vous rencontrez des erreurs de plugins, essayez de :
1. Réinstaller tflint : `brew reinstall tflint` (sur macOS)
2. Supprimer le cache : `rm -rf ~/.tflint.d/plugins` puis relancer `tflint --init`
3. Vérifier la version : `tflint --version`
