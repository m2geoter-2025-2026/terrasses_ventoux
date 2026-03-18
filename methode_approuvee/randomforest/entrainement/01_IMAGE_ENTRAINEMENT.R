# ==============================================================================
# SCRIPT R - IMAGE D'ENTRAÎNEMENT RANDOM FOREST
# ==============================================================================
# But : Construire l'image d'entraînement (features + label) pour la
#        classification des terrasses agricoles par Random Forest.
# Dépendances : terra, future, future.callr
# ==============================================================================

# Neutraliser le conflit PROJ avec PostgreSQL/PostGIS AVANT de charger les libs
# (PostgreSQL installe une base proj.db incompatible qui prend le dessus)
Sys.unsetenv("PROJ_LIB")
Sys.unsetenv("PROJ_DATA")

library(terra)
library(future)
library(future.callr)

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
# Chemins
masque_path <- "chemin/vers/votre/dossier/data/entrainement/masque_entrainement.tif"
image_path <- "chemin/vers/votre/dossier/data/entrainement/image_temp.tif"
output_temp_dir <- "chemin/vers/votre/dossier/output/temp_entrainement"
image_sortie_path <- "chemin/vers/votre/dossier/data/entrainement/image_entrainement.tif"

# Tailles de fenêtres pour les calculs focaux
window_sizes <- c(3, 7, 9, 11)

# Création des répertoires de sortie
dir.create(output_temp_dir, recursive = TRUE, showWarnings = FALSE)

# Calcul du temps de début
temps_debut <- Sys.time()
cat("--- DÉBUT DE L'ANALYSE :", format(temps_debut, "%H:%M:%S"), "---\n\n")

# ==============================================================================
# 2. LECTURE DES DONNÉES D'ENTRÉE
# ==============================================================================
cat("--- ÉTAPE 1 : Lecture des données d'entrée ---\n")

masque <- rast(masque_path)
image <- rast(image_path)
mnt <- image[[4]]

cat("  [OK] Masque :", basename(masque_path), "\n")
cat("  [OK] Image   :", basename(image_path), "\n")
cat("  [OK] MNT     : bande 4 extraite\n\n")

# ==============================================================================
# 3. FILTRAGE SPATIAL — BUFFER AUTOUR DES ZONES LABELISÉES
# ==============================================================================
cat("--- ÉTAPE 2 : Filtrage spatial (buffer 150 m autour des zones labelisées) ---\n")

masque_pour_distance <- masque
masque_pour_distance[masque == 1] <- NA

distance <- distance(masque_pour_distance)
zone_interet <- distance < 150

masque <- mask(masque, zone_interet, maskvalue = 0)
mnt <- mask(mnt, zone_interet, maskvalue = 0)
image <- mask(image, zone_interet, maskvalue = 0)

cat("  [OK] Filtrage spatial terminé\n\n")

# ==============================================================================
# 4. CALCUL DE LA PENTE ET DU NDVI — THREAD PRINCIPAL
# ==============================================================================
cat("--- ÉTAPE 3 : Calcul de la pente et du NDVI ---\n")

# === 4.1 Pente ================================================================
cat("  Calcul de la pente...\n")
pente <- terrain(mnt, v = "slope", unit = "degrees")
writeRaster(pente, file.path(output_temp_dir, "pente_temp.tif"), overwrite = TRUE)
cat("  [OK] Pente calculée et sauvegardée\n")

# === 4.2 NDVI (bande 1 = NIR, bande 2 = Rouge) ===============================
cat("  Calcul du NDVI...\n")
nir <- image[[1]]
red <- image[[2]]
ndvi <- (nir - red) / (nir + red)
names(ndvi) <- "ndvi"
writeRaster(ndvi, file.path(output_temp_dir, "ndvi.tif"), overwrite = TRUE)
cat("  [OK] NDVI calculé et sauvegardé\n\n")

# ==============================================================================
# 5. CALCULS FOCAUX EN PARALLÈLE — SD ET TRI PAR FENÊTRE
# ==============================================================================
cat("--- ÉTAPE 4 : Calculs focaux en parallèle (", length(window_sizes) * 2, "jobs) ---\n")

# === 5.1 Fonction écart-type de la pente sur fenêtre circulaire ==============
fn_sd <- function(radius, output_temp_dir) {
  library(terra)
  pente <- rast(file.path(output_temp_dir, "pente_temp.tif"))
  kernel <- focalMat(pente, d = radius, type = "circle")
  result <- focal(pente, kernel, sd, na.rm = TRUE)
  writeRaster(result, file.path(output_temp_dir, paste0("sd_r", radius, ".tif")), overwrite = TRUE)
  paste0("sd_r", radius, " ok")
}

# === 5.2 Fonction TRI (Terrain Ruggedness Index) sur fenêtre circulaire ======
fn_tri <- function(radius, output_temp_dir) {
  library(terra)
  pente <- rast(file.path(output_temp_dir, "pente_temp.tif"))
  kernel <- focalMat(pente, d = radius, type = "circle")

  tri_function <- function(x, na.rm = TRUE) {
    center <- x[length(x) %/% 2 + 1]
    if (is.na(center)) {
      return(NA)
    }
    sum(abs(x - center), na.rm = na.rm)
  }

  result <- focal(pente, kernel, tri_function, na.rm = TRUE)
  writeRaster(result, file.path(output_temp_dir, paste0("tri_r", radius, ".tif")), overwrite = TRUE)
  paste0("tri_r", radius, " ok")
}

# === 5.3 Lancement simultané des jobs ========================================
plan(multisession, workers = length(window_sizes) * 2)

futures_sd <- lapply(window_sizes, function(r) future(fn_sd(r, output_temp_dir), seed = TRUE))
futures_tri <- lapply(window_sizes, function(r) future(fn_tri(r, output_temp_dir), seed = TRUE))

for (f in futures_sd) cat("  [OK]", value(f), "\n")
for (f in futures_tri) cat("  [OK]", value(f), "\n")

plan(sequential)
cat("\n")

# ==============================================================================
# 6. ASSEMBLAGE DES FEATURES — RECHARGEMENT ET EMPILEMENT
# ==============================================================================
cat("--- ÉTAPE 5 : Assemblage des features ---\n")

feature_list <- c(
  list(pente, rast(file.path(output_temp_dir, "ndvi.tif"))),
  lapply(window_sizes, function(r) rast(file.path(output_temp_dir, paste0("sd_r", r, ".tif")))),
  lapply(window_sizes, function(r) rast(file.path(output_temp_dir, paste0("tri_r", r, ".tif"))))
)

feature_names <- c(
  "pente", "ndvi",
  paste0("sd_r", window_sizes),
  paste0("tri_r", window_sizes)
)

features <- feature_list[[1]]
for (i in 2:length(feature_list)) features <- c(features, feature_list[[i]])
names(features) <- feature_names

cat("  [OK]", length(feature_names), "features assemblées\n\n")

# ==============================================================================
# 7. CONSTRUCTION ET SAUVEGARDE DE L'IMAGE D'ENTRAÎNEMENT
# ==============================================================================
cat("--- ÉTAPE 6 : Construction et sauvegarde de l'image d'entraînement ---\n")

image_entrainement <- c(features, masque)
names(image_entrainement)[nlyr(image_entrainement)] <- "label"

writeRaster(image_entrainement, image_sortie_path, overwrite = TRUE)
cat("  [OK] Image d'entraînement sauvegardée :", basename(image_sortie_path), "\n\n")

# ==============================================================================
# 8. DIAGNOSTIC — DISTRIBUTION DES CLASSES ET BANDES
# ==============================================================================
cat("--- ÉTAPE 7 : Diagnostic ---\n")

cat("  Bandes créées :\n")
print(names(image_entrainement))

df <- as.data.frame(image_entrainement, na.rm = TRUE)

cat("\n  Distribution des classes :\n")
print(table(df$label))

cat("\n  Proportions (%) :\n")
print(round(prop.table(table(df$label)) * 100, 2))

cat("\n  Nombre total de bandes :", nlyr(image_entrainement), "\n")
cat("  Structure : 1 pente + 1 NDVI +", length(window_sizes), "fenêtres × 2 stats (SD + TRI) + 1 label\n\n")

# ==============================================================================
# FIN
# ==============================================================================
temps_fin <- Sys.time()
duree <- difftime(temps_fin, temps_debut, units = "secs")

cat("--- PROCESSUS TERMINÉ AVEC SUCCÈS ---\n")
cat("  Heure de début :", format(temps_debut, "%H:%M:%S"), "\n")
cat("  Heure de fin   :", format(temps_fin, "%H:%M:%S"), "\n")
cat(sprintf(
  "  Durée totale   : %d min %d sec\n",
  floor(as.numeric(duree) / 60),
  round(as.numeric(duree) %% 60)
))
