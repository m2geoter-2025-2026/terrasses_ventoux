# ==============================================================================
# SCRIPT R - FUSION ET FILTRAGE DES COUCHES
# ==============================================================================
# But : Filtrage et fusion des couches vectorielles pt_* (Terrasses).
# Dépendances : terra, sf, tictoc
# ==============================================================================

library(terra)
library(sf)
library(tictoc)

tic("TOTAL")
temps_debut <- Sys.time()
cat(sprintf("--- DÉBUT DU TRAITEMENT : %s ---\n", format(temps_debut, "%H:%M:%S")))

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
cat("--- ÉTAPE 1 : Configuration et listage des fichiers pt_* ---\n")

chemin_traite <- "chemin/vers/votre/dossier/output/TRAITE"
fichier_out <- "chemin/vers/votre/dossier/output/TERRASSES.gpkg"

# ==============================================================================
# 2. LISTE DES FICHIERS pt_*
# ==============================================================================

fichiers_pt <- list.files(chemin_traite,
  pattern = "^pt_.*\\.gpkg$",
  full.names = TRUE, recursive = TRUE
)

cat("Fichiers pt_* trouvés :", length(fichiers_pt), "\n\n")

# ==============================================================================
# 3. CHARGEMENT, FILTRAGE DES COUCHES
# ==============================================================================
cat("--- ÉTAPE 2 : Chargement et filtrage des couches par diagnostic et superficie ---\n")

couches <- lapply(fichiers_pt, function(f) {
  nom <- basename(f)
  cat("Traitement :", nom, "\n")

  couche <- st_read(f, quiet = TRUE)
  n_init <- nrow(couche)

  # Filtrage des entités avec au moins un diagnostic à 1
  couche <- couche[
    couche$diag_convexite == 1 |
      couche$diag_pente_moy == 1 |
      couche$diag_pente_dec10 == 1,
  ]
  cat("  → Filtre diagnostic  :", n_init - nrow(couche), "supprimés |", nrow(couche), "restants\n")

  # Filtrage superficie > 1000 m²
  n_avant <- nrow(couche)
  couche <- couche[couche$superficie <= 1000, ]
  cat("  → Filtre superficie  :", n_avant - nrow(couche), "supprimés |", nrow(couche), "restants\n")

  couche
})

# ==============================================================================
# 4. FUSION
# ==============================================================================
cat("\n--- ÉTAPE 3 : Fusion des couches ---\n")

terrasses <- do.call(rbind, couches)
cat("Total polygones fusionnés :", nrow(terrasses), "\n")

# ==============================================================================
# 5. SAUVEGARDE
# ==============================================================================
cat("\n--- ÉTAPE 4 : Sauvegarde du résultat ---\n")

cat("Sauvegarde →", fichier_out, "\n")
st_write(terrasses, fichier_out, delete_dsn = TRUE)

cat("\n--- PROCESSUS TERMINÉ AVEC SUCCÈS ---\n")
toc()
