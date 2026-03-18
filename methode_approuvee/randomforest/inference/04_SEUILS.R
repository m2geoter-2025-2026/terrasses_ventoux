# ==============================================================================
# SCRIPT R - APPLICATION DES SEUILS
# ==============================================================================
# But : Appliquer différents seuils de probabilité sur le raster issu
#       du Random Forest pour extraire la classe d'intérêt (terrasses).
# Dépendances : terra
# ==============================================================================

library(terra)

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
cat("--- ÉTAPE 1 : Configuration et nettoyage du dossier de sortie ---\n")

input_path <- "chemin/vers/votre/dossier/output/RF.tif"
output_dir <- "chemin/vers/votre/dossier/output/seuils"

bande      <- 2      # Bande probabilité classe terrasse
pas        <- 0.05   # Pas entre les seuils
seuil_min  <- 0.2    # Seuil minimum
seuil_max  <- 0.6    # Seuil maximum

# Création du dossier de sortie s'il n'existe pas
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Vider le dossier output
file.remove(list.files(output_dir, full.names = TRUE))

# ==============================================================================
# 2. CHARGEMENT DU RASTER
# ==============================================================================
cat("--- ÉTAPE 2 : Chargement du raster ---\n")

raster <- rast(input_path)
bande_proba <- raster[[bande]]

# ==============================================================================
# 3. APPLICATION DES SEUILS
# ==============================================================================
cat("--- ÉTAPE 3 : Binarisation selon les seuils ---\n")

seuils <- seq(seuil_min, seuil_max, by = pas)

for (seuil in seuils) {
  
  # Nom de fichier basé sur le seuil
  seuil_label <- formatC(seuil, format = "f", digits = 2)
  output_name <- paste0("terrasses_seuil_", gsub("\\.", "", seuil_label))
  output_path <- file.path(output_dir, paste0(output_name, ".tif"))
  
  cat("Application du seuil :", seuil_label, "...\n")
  
  # Binarisation : 1 si prob >= seuil, 0 sinon
  raster_seuil <- ifel(bande_proba >= seuil, 1, 0)
  
  # Sauvegarde
  writeRaster(
    raster_seuil,
    output_path,
    datatype = "INT1U",   # Byte : valeurs 0/1
    overwrite = TRUE
  )
}

# ==============================================================================
# 4. RÉCAPITULATIF
# ==============================================================================
cat("--- PROCESSUS TERMINÉ AVEC SUCCÈS ---\n")
cat("Nombre de rasters créés :", length(seuils), "\n")
cat("Dossier de sortie       :", output_dir, "\n")
cat("Seuils appliqués        :", paste(formatC(seuils, format = "f", digits = 2), collapse = " | "), "\n")