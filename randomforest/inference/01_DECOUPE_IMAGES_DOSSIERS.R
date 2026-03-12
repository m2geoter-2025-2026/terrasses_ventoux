# ==============================================================================
# SCRIPT R - DÉCOUPAGE IMAGES ET DOSSIERS
# ==============================================================================
# But : Traitement géographique par dalle - Découpage MNT et Ortho JP2.
# Dépendances : sf, terra
# ==============================================================================

# Neutraliser le conflit PROJ avec PostgreSQL/PostGIS AVANT de charger les libs
# (PostgreSQL installe une base proj.db incompatible qui prend le dessus)
Sys.unsetenv("PROJ_LIB")
Sys.unsetenv("PROJ_DATA")

library(sf)
library(terra)

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
# Chemins
gpkg_path <- "chemin/vers/votre/dossier/data/DALLE_V2.gpkg"
mnt_path <- "chemin/vers/votre/dossier/data/mnt.tif"
ortho_dir <- "chemin/vers/votre/dossier/data/ortho"
output_dir <- "chemin/vers/votre/dossier/output/dcoup"

# Création des répertoires de sortie
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# ==============================================================================
# 2. LECTURE DU CARROYAGE ET RECHERCHE DES FICHIERS
# ==============================================================================
cat("--- ÉTAPE 1 : Lecture du carroyage et recherche des fichiers ---\n")

dalles <- st_read(gpkg_path, quiet = TRUE)

cat("Nombre de dalles :", nrow(dalles), "\n")
cat("Champs disponibles :", paste(names(dalles), collapse = ", "), "\n\n")

jp2_files <- list.files(ortho_dir, pattern = "\\.jp2$", recursive = TRUE, full.names = TRUE)
cat("Fichiers JP2 trouvés :", length(jp2_files), "\n\n")

# ==============================================================================
# 3. TRAITEMENT PAR DALLE (DÉCOUPAGE MNT ET ORTHOPHOTOS)
# ==============================================================================
cat("--- ÉTAPE 2 : Traitement et découpage par dalle ---\n")

for (i in seq_len(nrow(dalles))) {
  dalle <- dalles[i, ]
  nom_concat <- dalle$nom_concat

  cat("--- Traitement dalle", i, "/", nrow(dalles), ":", nom_concat, "---\n")

  # === 3.1 Création du dossier de sortie =====================================
  dossier_sortie <- file.path(output_dir, nom_concat)
  dir.create(dossier_sortie, recursive = TRUE, showWarnings = FALSE)

  # Convertir la dalle en vecteur terra (même CRS, pas de reprojection)
  dalle_vect <- vect(dalle)

  # === 3.2 Découpage du MNT ==================================================
  tryCatch(
    {
      mnt <- rast(mnt_path)

      # Forcer le même CRS sur le vecteur sans reprojection
      crs(dalle_vect) <- crs(mnt)

      mnt_crop <- crop(mnt, dalle_vect)
      mnt_mask <- mask(mnt_crop, dalle_vect)

      mnt_out <- file.path(dossier_sortie, paste0("mnt_", nom_concat, ".tif"))
      writeRaster(mnt_mask, mnt_out, overwrite = TRUE)

      cat("  [OK] MNT :", basename(mnt_out), "\n")
    },
    error = function(e) {
      cat("  [ERREUR] MNT :", conditionMessage(e), "\n")
    }
  )

  # === 3.3 Recherche du fichier JP2 correspondant ============================
  jp2_match <- jp2_files[grepl(nom_concat, jp2_files, fixed = TRUE)]

  if (length(jp2_match) == 0) {
    cat("  [ATTENTION] Aucun JP2 trouvé pour :", nom_concat, "\n\n")
    next
  }
  if (length(jp2_match) > 1) {
    cat("  [ATTENTION] Plusieurs JP2 trouvés, premier retenu :", basename(jp2_match[1]), "\n")
    jp2_match <- jp2_match[1]
  }

  cat("  JP2 :", basename(jp2_match), "\n")

  # === 3.4 Découpage et rééchantillonnage de l'orthophoto ====================
  tryCatch(
    {
      ortho <- rast(jp2_match)
      ortho2b <- ortho[[1:2]]

      # Forcer le même CRS sur le vecteur sans reprojection
      dalle_vect2 <- vect(dalle)
      crs(dalle_vect2) <- crs(ortho2b)

      ortho_crop <- crop(ortho2b, dalle_vect2)
      ortho_mask <- mask(ortho_crop, dalle_vect2)

      # Rééchantillonnage à 1 mètre
      rast_cible <- rast(
        ext = ext(ortho_mask),
        res = 1,
        crs = crs(ortho_mask)
      )
      ortho_1m <- resample(ortho_mask, rast_cible, method = "bilinear")

      ortho_out <- file.path(dossier_sortie, paste0("ortho_", nom_concat, ".tif"))
      writeRaster(ortho_1m, ortho_out,
        overwrite = TRUE,
        gdal = c("COMPRESS=LZW", "TILED=YES")
      )

      cat("  [OK] Ortho 1m 2 bandes :", basename(ortho_out), "\n")
    },
    error = function(e) {
      cat("  [ERREUR] Ortho :", conditionMessage(e), "\n")
    }
  )

  cat("\n")
}

cat("--- PROCESSUS TERMINÉ AVEC SUCCÈS ---\n")
