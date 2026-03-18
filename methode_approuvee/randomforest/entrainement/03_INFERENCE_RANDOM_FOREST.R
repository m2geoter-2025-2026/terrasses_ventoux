# ==============================================================================
# SCRIPT R - INFÉRENCE RANDOM FOREST
# ==============================================================================
# But : Appliquer le modèle Random Forest entraîné sur de nouvelles
#        données (MNT et image) pour détecter les terrasses agricoles.
# Dépendances : terra, ranger, future, future.callr
# ==============================================================================

# Neutraliser le conflit PROJ avec PostgreSQL/PostGIS AVANT de charger les libs
# (PostgreSQL installe une base proj.db incompatible qui prend le dessus)
Sys.unsetenv("PROJ_LIB")
Sys.unsetenv("PROJ_DATA")

library(terra)
library(ranger)
library(future)
library(future.callr)

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
# Chemins
modele_path           <- "chemin/vers/votre/dossier/output/rf_terrasses.rds"
mnt_path              <- "chemin/vers/votre/dossier/data/inference_5/mnt.tif"
image_path            <- "chemin/vers/votre/dossier/data/inference_5/image.tif"
output_temp_dir       <- "chemin/vers/votre/dossier/output/temp_inference"
prediction_class_path <- "chemin/vers/votre/dossier/output/terrasses_rf_inference.tif"
prediction_prob_path  <- "chemin/vers/votre/dossier/output/terrasses_rf_probabilites.tif"

# Tailles de fenêtres pour les calculs focaux
window_sizes <- c(3, 7, 9, 11)

# Création des répertoires de sortie
dir.create(output_temp_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(prediction_class_path), recursive = TRUE, showWarnings = FALSE)

# Calcul du temps de début
temps_debut <- Sys.time()
cat("--- DÉBUT DE L'ANALYSE :", format(temps_debut, "%H:%M:%S"), "---\n\n")

# ==============================================================================
# 2. CHARGEMENT DU MODÈLE ET DES DONNÉES
# ==============================================================================
cat("--- ÉTAPE 1 : Chargement du modèle et des données ---\n")

rf_model <- readRDS(modele_path)
mnt      <- rast(mnt_path)
image    <- rast(image_path)

cat("  [OK] Modèle chargé :", basename(modele_path), "\n")
cat("  [OK] MNT chargé    :", basename(mnt_path), "\n")
cat("  [OK] Image chargée :", basename(image_path), "\n\n")

# ==============================================================================
# 3. CALCUL DE LA PENTE ET DU NDVI — THREAD PRINCIPAL
# ==============================================================================
cat("--- ÉTAPE 2 : Calcul de la pente et du NDVI ---\n")

# === 3.1 Pente ================================================================
cat("  Calcul de la pente...\n")
pente <- terrain(mnt, v = "slope", unit = "degrees")
writeRaster(pente, file.path(output_temp_dir, "pente_temp_inf.tif"), overwrite = TRUE)
cat("  [OK] Pente calculée et sauvegardée\n")

# === 3.2 NDVI (bande 1 = NIR, bande 2 = Rouge) ===============================
cat("  Calcul du NDVI...\n")
nir  <- image[[1]]
red  <- image[[2]]
ndvi <- (nir - red) / (nir + red)
names(ndvi) <- "ndvi"
writeRaster(ndvi, file.path(output_temp_dir, "inf_ndvi.tif"), overwrite = TRUE)
cat("  [OK] NDVI calculé et sauvegardé\n\n")

# ==============================================================================
# 4. CALCULS FOCAUX EN PARALLÈLE — SD ET TRI PAR FENÊTRE
# ==============================================================================
cat("--- ÉTAPE 3 : Calculs focaux en parallèle (", length(window_sizes) * 2, "jobs) ---\n")

# === 4.1 Fonction écart-type de la pente sur fenêtre circulaire ==============
fn_sd <- function(radius, output_temp_dir) {
  library(terra)
  pente  <- rast(file.path(output_temp_dir, "pente_temp_inf.tif"))
  kernel <- focalMat(pente, d = radius, type = "circle")
  result <- focal(pente, kernel, sd, na.rm = TRUE)
  writeRaster(result, file.path(output_temp_dir, paste0("inf_sd_r", radius, ".tif")), overwrite = TRUE)
  paste0("sd_r", radius, " ok")
}

# === 4.2 Fonction TRI (Terrain Ruggedness Index) sur fenêtre circulaire ======
fn_tri <- function(radius, output_temp_dir) {
  library(terra)
  pente  <- rast(file.path(output_temp_dir, "pente_temp_inf.tif"))
  kernel <- focalMat(pente, d = radius, type = "circle")
  
  tri_function <- function(x, na.rm = TRUE) {
    center <- x[length(x) %/% 2 + 1]
    if (is.na(center)) {
      return(NA)
    }
    sum(abs(x - center), na.rm = na.rm)
  }
  
  result <- focal(pente, kernel, tri_function, na.rm = TRUE)
  writeRaster(result, file.path(output_temp_dir, paste0("inf_tri_r", radius, ".tif")), overwrite = TRUE)
  paste0("tri_r", radius, " ok")
}

# === 4.3 Lancement simultané des jobs ========================================
plan(multisession, workers = length(window_sizes) * 2)

futures_sd  <- lapply(window_sizes, function(r) future(fn_sd(r,  output_temp_dir), seed = TRUE))
futures_tri <- lapply(window_sizes, function(r) future(fn_tri(r, output_temp_dir), seed = TRUE))

for (f in futures_sd)  cat("  [OK]", value(f), "\n")
for (f in futures_tri) cat("  [OK]", value(f), "\n")

plan(sequential)
cat("\n")

# ==============================================================================
# 5. ASSEMBLAGE DE L'IMAGE D'INFÉRENCE
# ==============================================================================
cat("--- ÉTAPE 4 : Assemblage des features ---\n")

ref <- rast(file.path(output_temp_dir, "pente_temp_inf.tif"))

feature_list <- c(
  list(ref, rast(file.path(output_temp_dir, "inf_ndvi.tif"))),
  lapply(window_sizes, function(r) rast(file.path(output_temp_dir, paste0("inf_sd_r",  r, ".tif")))),
  lapply(window_sizes, function(r) rast(file.path(output_temp_dir, paste0("inf_tri_r", r, ".tif"))))
)

# Forcer la cohérence spatiale de tous les rasters sur la référence
feature_list <- lapply(feature_list, function(r) {
  if (!compareGeom(ref, r, stopOnError = FALSE)) {
    return(resample(r, ref, method = "bilinear"))
  } else {
    return(r)
  }
})

feature_names <- c(
  "pente", "ndvi",
  paste0("sd_r",  window_sizes),
  paste0("tri_r", window_sizes)
)

features <- feature_list[[1]]
for (i in 2:length(feature_list)) features <- c(features, feature_list[[i]])
names(features) <- feature_names

cat("  [OK]", length(feature_names), "features assemblées\n\n")

# ==============================================================================
# 6. VÉRIFICATION DE COMPATIBILITÉ AVEC LE MODÈLE
# ==============================================================================
cat("--- ÉTAPE 5 : Vérification de la compatibilité avec le modèle ---\n")

expected_names <- rf_model$forest$independent.variable.names

cat("  Variables attendues :", paste(expected_names, collapse = ", "), "\n")
cat("  Variables générées  :", paste(names(features), collapse = ", "), "\n")

if (!identical(names(features), expected_names)) {
  cat("  [ATTENTION] Réordonnancement des bandes pour correspondre au modèle...\n")
  features <- features[[expected_names]]
  cat("  Ordre final corrigé :", paste(names(features), collapse = ", "), "\n")
} else {
  cat("  [OK] Concordance parfaite des variables\n")
}
cat("\n")

# ==============================================================================
# 7. INFÉRENCE SUR LA NOUVELLE IMAGE
# ==============================================================================
n_threads <- parallel::detectCores() - 1
cat("--- ÉTAPE 6 : Inférence Random Forest (", n_threads, "threads) ---\n")

cat("  Début de la prédiction (probabilités)...\n")
pred_prob <- predict(features, rf_model, fun = function(model, data) {
  p <- predict(model, data)$predictions
  return(p)
}, na.rm = TRUE)

cat("  Calcul de la classe majoritaire...\n")
pred_class <- app(pred_prob, which.max)

cat("  [OK] Inférence terminée\n\n")

# ==============================================================================
# 8. SAUVEGARDE DES RÉSULTATS
# ==============================================================================
cat("--- ÉTAPE 7 : Sauvegarde des résultats ---\n")

writeRaster(pred_class, prediction_class_path, overwrite = TRUE)
cat("  [OK] Classes sauvegardées      :", basename(prediction_class_path), "\n")

writeRaster(pred_prob,  prediction_prob_path,  overwrite = TRUE)
cat("  [OK] Probabilités sauvegardées :", basename(prediction_prob_path), "\n\n")

# ==============================================================================
# FIN
# ==============================================================================
temps_fin <- Sys.time()
duree     <- difftime(temps_fin, temps_debut, units = "secs")

cat("--- PROCESSUS TERMINÉ AVEC SUCCÈS ---\n")
cat("  Bandes utilisées :", nlyr(features), "\n")
cat("  Structure        : 1 pente + 1 NDVI +", length(window_sizes), "fenêtres × 2 stats (SD + TRI)\n")
cat("  Heure de début   :", format(temps_debut, "%H:%M:%S"), "\n")
cat("  Heure de fin     :", format(temps_fin,   "%H:%M:%S"), "\n")
cat(sprintf(
  "  Durée totale     : %d min %d sec\n",
  floor(as.numeric(duree) / 60),
  round(as.numeric(duree) %% 60)
))
