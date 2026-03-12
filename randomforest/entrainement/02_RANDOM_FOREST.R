# ==============================================================================
# SCRIPT R - ENTRAÎNEMENT RANDOM FOREST
# ==============================================================================
# But : Entraîner le modèle Random Forest pour la classification des
#        terrasses agricoles à partir de l'image d'entraînement.
# Dépendances : terra, ranger, ggplot2, dplyr
# ==============================================================================

# Neutraliser le conflit PROJ avec PostgreSQL/PostGIS AVANT de charger les libs
# (PostgreSQL installe une base proj.db incompatible qui prend le dessus)
Sys.unsetenv("PROJ_LIB")
Sys.unsetenv("PROJ_DATA")

library(terra)
library(ranger)
library(ggplot2)
library(dplyr)

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
# Chemins
image_entrainement_path <- "chemin/vers/votre/dossier/data/entrainement/image_entrainement.tif"
modele_sortie_path      <- "chemin/vers/votre/dossier/output/rf_terrasses_big.rds"
graphique_sortie_path   <- "chemin/vers/votre/dossier/output/importance_variable.png"

# Création des répertoires de sortie
dir.create(dirname(modele_sortie_path),    recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(graphique_sortie_path), recursive = TRUE, showWarnings = FALSE)

# Paramètres du modèle
num.threads <- parallel::detectCores() - 1

# Calcul du temps de début
temps_debut <- Sys.time()
cat("--- DÉBUT DE L'ANALYSE :", format(temps_debut, "%H:%M:%S"), "---\n\n")

# ==============================================================================
# 2. LECTURE DE L'IMAGE D'ENTRAÎNEMENT
# ==============================================================================
cat("--- ÉTAPE 1 : Lecture de l'image d'entraînement ---\n")

image_entrainement <- rast(image_entrainement_path)

cat("  [OK] Image chargée :", basename(image_entrainement_path), "\n")
cat("  Nombre de bandes :", nlyr(image_entrainement), "\n\n")

# ==============================================================================
# 3. PRÉPARATION DU JEU D'ENTRAÎNEMENT
# ==============================================================================
cat("--- ÉTAPE 2 : Préparation du jeu d'entraînement ---\n")

df <- as.data.frame(image_entrainement, na.rm = TRUE)
df <- df[, !names(df) %in% c("x", "y")]  # supprimer les coordonnées si présentes
colnames(df)[ncol(df)] <- "label"
df$label <- as.factor(df$label)

cat("  Distribution des classes :\n")
print(table(df$label))
cat("  Ratio classe 1 / classe 0 :", round(sum(df$label == 1) / sum(df$label == 0), 3), "\n")
cat("  Nombre total de pixels     :", nrow(df), "\n\n")

# ==============================================================================
# 4. ENTRAÎNEMENT DU MODÈLE RANDOM FOREST
# ==============================================================================
cat("--- ÉTAPE 3 : Entraînement Random Forest (", num.threads, "threads) ---\n")

set.seed(42)
rf_model <- ranger(
  label ~ .,
  data         = df,
  num.trees    = 30,
  importance   = "permutation",            # retirer pour gagner en performance
  probability  = TRUE,
  case.weights = 1 / table(df$label)[df$label],  # équilibrage des classes
  num.threads  = num.threads
)

cat("  [OK] Entraînement terminé\n")
cat("  Erreur OOB finale :", round(rf_model$prediction.error, 4), "(plus c'est bas, mieux c'est)\n\n")

# ==============================================================================
# 5. SAUVEGARDE DU MODÈLE
# ==============================================================================
cat("--- ÉTAPE 4 : Sauvegarde du modèle ---\n")

saveRDS(rf_model, modele_sortie_path)
cat("  [OK] Modèle sauvegardé :", basename(modele_sortie_path), "\n\n")

# ==============================================================================
# 6. IMPORTANCE DES VARIABLES
# ==============================================================================
cat("--- ÉTAPE 5 : Calcul et visualisation de l'importance des variables ---\n")

imp <- data.frame(
  Variable   = names(rf_model$variable.importance),
  Importance = rf_model$variable.importance
) |> arrange(desc(Importance))

cat("  Importance des variables (ordre décroissant) :\n")
print(imp)

p <- ggplot(imp, aes(x = reorder(Variable, Importance), y = Importance)) +
  geom_col(fill = "steelblue") +
  coord_flip() +
  labs(
    title = "Importance des variables (permutation)",
    x     = "Variable",
    y     = "Perte de précision"
  ) +
  theme_minimal()

print(p)
ggsave(filename = graphique_sortie_path, plot = p)
cat("  [OK] Graphique sauvegardé :", basename(graphique_sortie_path), "\n\n")

# ==============================================================================
# FIN
# ==============================================================================
temps_fin <- Sys.time()
duree     <- difftime(temps_fin, temps_debut, units = "secs")

cat("--- PROCESSUS TERMINÉ AVEC SUCCÈS ---\n")
cat("  Heure de début :", format(temps_debut, "%H:%M:%S"), "\n")
cat("  Heure de fin   :", format(temps_fin,   "%H:%M:%S"), "\n")
cat(sprintf(
  "  Durée totale   : %d min %d sec\n",
  floor(as.numeric(duree) / 60),
  round(as.numeric(duree) %% 60)
))
