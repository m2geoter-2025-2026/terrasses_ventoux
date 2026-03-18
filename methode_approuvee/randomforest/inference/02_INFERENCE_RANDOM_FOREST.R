# ==============================================================================
# SCRIPT R - INFÉRENCE RANDOM FOREST PAR DALLE
# ==============================================================================
# But : Inférence par dalle (MNT + Ortho) avec le modèle Random Forest.
# Dépendances : terra, ranger
# ==============================================================================

Sys.unsetenv("PROJ_LIB")
Sys.unsetenv("PROJ_DATA")

library(terra)
library(ranger)

temps_debut <- Sys.time()
cat(sprintf("--- DÉBUT DU TRAITEMENT : %s ---\n", format(temps_debut, "%H:%M:%S")))

# ==============================================================================
# 0. UTILITAIRE : AFFICHAGE ÉTAPE EN COURS
# ==============================================================================
log_etape <- function(nom_dalle, i, n_total, etape, detail = "") {
  cat(sprintf(
    "[%d/%d] %s | %s %s\n",
    i, n_total, nom_dalle, etape,
    if (nchar(detail) > 0) paste0("— ", detail) else ""
  ))
}

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
cat("--- ÉTAPE 1 : Chargement des paramètres et du modèle ---\n")

dcoup_dir <- "chemin/vers/votre/dossier/output/a_traiter"
model_path <- "chemin/vers/votre/dossier/output/rf_terrasses.rds"

cat("Chargement du modèle RF...\n")
rf_model <- readRDS(model_path)
cat("Modèle chargé.\n\n")

dossiers <- list.dirs(dcoup_dir, recursive = FALSE)
n_total <- length(dossiers)
cat("Dossiers trouvés :", n_total, "\n\n")

# ==============================================================================
# 2. FONCTION D'INFÉRENCE
# ==============================================================================
fn_inference_dalle <- function(mnt_dalle, ortho_dalle_r, nom_dalle,
                               dossier_sortie, rf_model, i, n_total) {
  window_sizes <- c(3, 7, 9, 11)

  tmp_dir <- file.path("chemin/vers/votre/dossier/output", "temp_inference", nom_dalle)
  dir.create(tmp_dir, showWarnings = FALSE, recursive = TRUE)

  # === 2.1 Pente ==============================================================
  log_etape(nom_dalle, i, n_total, "Calcul de la pente")
  pente <- terrain(mnt_dalle, v = "slope", unit = "degrees")
  path_pente <- file.path(tmp_dir, "pente.tif")
  writeRaster(pente, path_pente, overwrite = TRUE)

  # === 2.2 NDVI ===============================================================
  log_etape(nom_dalle, i, n_total, "Calcul du NDVI")
  nir <- ortho_dalle_r[[1]]
  red <- ortho_dalle_r[[2]]
  ndvi <- (nir - red) / (nir + red)
  names(ndvi) <- "ndvi"
  path_ndvi <- file.path(tmp_dir, "ndvi.tif")
  writeRaster(ndvi, path_ndvi, overwrite = TRUE)

  # === 2.3 Focales SD et TRI ==================================================
  tri_function <- function(x, na.rm = TRUE) {
    center <- x[length(x) %/% 2 + 1]
    if (is.na(center)) {
      return(NA)
    }
    sum(abs(x - center), na.rm = na.rm)
  }

  for (r in window_sizes) {
    log_etape(nom_dalle, i, n_total, "Focales SD + TRI", paste0("fenêtre ", r, "m"))
    pente_r <- rast(path_pente)
    kernel <- focalMat(pente_r, d = r, type = "circle")

    sd_r <- focal(pente_r, kernel, sd, na.rm = TRUE)
    tri_r <- focal(pente_r, kernel, tri_function, na.rm = TRUE)

    writeRaster(sd_r, file.path(tmp_dir, paste0("sd_r", r, ".tif")), overwrite = TRUE)
    writeRaster(tri_r, file.path(tmp_dir, paste0("tri_r", r, ".tif")), overwrite = TRUE)
  }

  # === 2.4 Assemblage des features ============================================
  log_etape(nom_dalle, i, n_total, "Assemblage des variables")

  ref <- rast(path_pente)

  feature_list <- list(
    ref,
    rast(path_ndvi),
    rast(file.path(tmp_dir, "sd_r3.tif")),
    rast(file.path(tmp_dir, "tri_r3.tif")),
    rast(file.path(tmp_dir, "sd_r7.tif")),
    rast(file.path(tmp_dir, "tri_r7.tif")),
    rast(file.path(tmp_dir, "sd_r9.tif")),
    rast(file.path(tmp_dir, "tri_r9.tif")),
    rast(file.path(tmp_dir, "sd_r11.tif")),
    rast(file.path(tmp_dir, "tri_r11.tif"))
  )

  feature_names <- c(
    "pente", "ndvi",
    "sd_r3", "tri_r3",
    "sd_r7", "tri_r7",
    "sd_r9", "tri_r9",
    "sd_r11", "tri_r11"
  )

  feature_list <- lapply(feature_list, function(rx) {
    if (!compareGeom(ref, rx, stopOnError = FALSE)) {
      resample(rx, ref, method = "bilinear")
    } else {
      rx
    }
  })

  features <- feature_list[[1]]
  for (k in 2:length(feature_list)) features <- c(features, feature_list[[k]])
  names(features) <- feature_names

  expected_names <- rf_model$forest$independent.variable.names
  if (!identical(names(features), expected_names)) features <- features[[expected_names]]

  # === 2.5 Prédiction =========================================================
  log_etape(nom_dalle, i, n_total, "Prédiction Random Forest")
  pred_prob <- predict(features, rf_model, fun = function(model, data) {
    predict(model, data)$predictions
  }, na.rm = TRUE)

  # === 2.6 Sauvegarde =========================================================
  log_etape(nom_dalle, i, n_total, "Sauvegarde du résultat")
  path_sortie <- file.path(dossier_sortie, paste0("rf_", nom_dalle, ".tif"))
  writeRaster(pred_prob, path_sortie,
    overwrite = TRUE,
    gdal = c("COMPRESS=LZW", "TILED=YES")
  )

  unlink(tmp_dir, recursive = TRUE)

  return(path_sortie)
}

# ==============================================================================
# 3. BOUCLE SÉQUENTIELLE D'INFÉRENCE
# ==============================================================================
cat("--- ÉTAPE 2 : Inférence par dalle ---\n")

resultats <- list()

for (idx in seq_along(dossiers)) {
  dossier <- dossiers[idx]
  nom_dalle <- basename(dossier)
  t0 <- Sys.time()

  cat(sprintf("\n--- Traitement dalle %d / %d : %s ---\n", idx, n_total, nom_dalle))

  tryCatch(
    {
      log_etape(nom_dalle, idx, n_total, "Lecture MNT + Orthophoto")

      mnt_file <- list.files(dossier, pattern = "^mnt_", full.names = TRUE)
      ortho_file <- list.files(dossier, pattern = "^ortho_", full.names = TRUE)

      if (length(mnt_file) == 0) stop("MNT introuvable")
      if (length(ortho_file) == 0) stop("Orthophoto introuvable")

      mnt_r <- rast(mnt_file[1])
      ortho_r <- rast(ortho_file[1])

      chemin_rf <- fn_inference_dalle(
        mnt_dalle      = mnt_r,
        ortho_dalle_r  = ortho_r,
        nom_dalle      = nom_dalle,
        dossier_sortie = dossier,
        rf_model       = rf_model,
        i              = idx,
        n_total        = n_total
      )

      duree_dalle <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")))
      cat(sprintf("  ✔ Terminé en %d sec -> %s\n", duree_dalle, basename(chemin_rf)))

      resultats[[nom_dalle]] <- list(statut = "OK", rf = chemin_rf, duree = duree_dalle)
    },
    error = function(e) {
      duree_dalle <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")))
      cat(sprintf("  ✘ ERREUR : %s  (%d sec)\n", conditionMessage(e), duree_dalle))
      resultats[[nom_dalle]] <<- list(statut = "ERREUR", message = conditionMessage(e), duree = duree_dalle)
    }
  )
}

# ==============================================================================
# 4. NETTOYAGE TEMPORAIRE
# ==============================================================================
cat("--- ÉTAPE 3 : Nettoyage des fichiers temporaires ---\n")

if (dir.exists("chemin/vers/votre/dossier/output/temp_inference")) {
  if (length(list.files("chemin/vers/votre/dossier/output/temp_inference", recursive = TRUE)) == 0) {
    unlink("chemin/vers/votre/dossier/output/temp_inference", recursive = TRUE)
  }
}

# ==============================================================================
# 5. RAPPORT FINAL
# ==============================================================================
temps_fin <- Sys.time()
duree_tot <- difftime(temps_fin, temps_debut, units = "secs")

cat("\n--- RAPPORT FINAL ---\n")
for (nm in names(resultats)) {
  r <- resultats[[nm]]
  if (r$statut == "OK") {
    cat(sprintf("  [OK]     %-20s  %d sec\n", nm, r$duree))
  } else {
    cat(sprintf("  [ERREUR] %-20s  %s\n", nm, r$message))
  }
}

cat("\n--- PROCESSUS TERMINÉ AVEC SUCCÈS ---\n")
cat(sprintf(
  "Durée totale   : %d min %d sec\n",
  floor(as.numeric(duree_tot) / 60),
  round(as.numeric(duree_tot) %% 60)
))
