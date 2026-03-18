# ==============================================================================
# SCRIPT R - FUSION DES RASTERS
# ==============================================================================
# But : Fusion des rasters rf_*.tif depuis output/TRAITE et sauvegarde 
#       du résultat sous forme d'un unique GeoTIFF.
# Dépendances : terra
# ==============================================================================

library(terra)

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
cat("--- ÉTAPE 1 : Définition des chemins et listage des fichiers ---\n")

racine <- "chemin/vers/votre/dossier/output/TRAITE"
dest   <- "chemin/vers/votre/dossier/output/RF.tif"

# --- Création du dossier de destination si besoin ---
if (!dir.exists(dirname(dest))) {
  dir.create(dirname(dest), recursive = TRUE)
}

# --- Lister tous les fichiers rf_*.tif dans les sous-dossiers ---
sous_dossiers <- list.dirs(racine, full.names = TRUE, recursive = FALSE)

fichiers_rf <- unlist(lapply(sous_dossiers, function(d) {
  list.files(d, pattern = "^rf_.*\\.tif$", full.names = TRUE, recursive = FALSE)
}))

cat(sprintf("Fichiers rf_*.tif trouvés : %d\n", length(fichiers_rf)))
print(fichiers_rf)

if (length(fichiers_rf) == 0) {
  stop("Aucun fichier rf_*.tif trouvé dans les sous-dossiers de ", racine)
}

# ==============================================================================
# 2. CHARGEMENT ET FUSION DES RASTERS
# ==============================================================================
cat("--- ÉTAPE 2 : Chargement et fusion des rasters ---\n")

# --- Charger tous les rasters ---
rasters <- lapply(fichiers_rf, rast)

# --- Fusionner (mosaic) ---
cat("Fusion en cours...\n")

if (length(rasters) == 1) {
  fusion <- rasters[[1]]
} else {
  fusion <- do.call(mosaic, rasters)
}

# ==============================================================================
# 3. SAUVEGARDE DU RÉSULTAT
# ==============================================================================
cat("--- ÉTAPE 3 : Sauvegarde du raster fusionné ---\n")

writeRaster(fusion, dest, overwrite = TRUE)

cat(sprintf("Raster fusionné enregistré : %s\n", dest))
print(fusion)

cat("--- PROCESSUS TERMINÉ AVEC SUCCÈS ---\n")
