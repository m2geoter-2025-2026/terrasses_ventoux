# ==============================================================================
# SCRIPT R - POST-TRAITEMENT DES RÉSULTATS (BATCH)
# ==============================================================================
# But : Post-traitement parallèle des résultats Random Forest (Terrasses).
#       Filtres, vectorisation, lissage et indices géométriques.
# Dépendances : terra, sf, smoothr, rmapshaper, tictoc, parallel
# ==============================================================================

library(terra)
library(sf)
library(smoothr)
library(rmapshaper)
library(tictoc)
library(parallel)

tic("TOTAL")
temps_debut <- Sys.time()
cat(sprintf("--- DÉBUT DU TRAITEMENT : %s ---\n", format(temps_debut, "%H:%M:%S")))

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
cat("--- ÉTAPE 1 : Configuration et listage des dossiers à traiter ---\n")

chemin_traite <- "chemin/vers/votre/dossier/output/TRAITE"

# --- Liste des dossiers contenant les résultats RF ---
dossiers <- list.dirs(chemin_traite, full.names = TRUE, recursive = FALSE)
dossiers <- dossiers[sapply(dossiers, function(d) {
  length(list.files(d, pattern = "^rf_.*\\.tif$")) > 0
})]

cat("Dossiers à traiter :", length(dossiers), "\n\n")

# ==============================================================================
# 2. DÉFINITION DE LA FONCTION DE POST-TRAITEMENT
# ==============================================================================

traiter_dossier <- function(dossier) {
  nom_dossier <- basename(dossier)
  fichier_out <- file.path(dossier, paste0("pt_", nom_dossier, ".gpkg"))
  fichier_rf <- list.files(dossier, pattern = "^rf_.*\\.tif$", full.names = TRUE)[1]
  fichier_mnt <- list.files(dossier, pattern = "^mnt_.*\\.tif$", full.names = TRUE)[1]

  log <- function(...) cat("[", nom_dossier, "]", ..., "\n")

  tryCatch(
    {
      # === 2.1 Chargement bande 2 + seuillage à 0.25 ==========================
      log("Chargement bande 2 et seuillage à 0.25...")
      r <- rast(fichier_rf)[[2]]
      r <- ifel(r >= 0.25, 1, 0)

      # === 2.2 Filtre majoritaire 5x5 =========================================
      log("Filtre majoritaire 5x5...")
      filtre_5 <- focal(r, w = 5, fun = "modal", na.rm = TRUE)

      # === 2.3 Vectorisation par patch contigu ================================
      log("Étiquetage des patches...")
      filtre_5[filtre_5 == 0] <- NA
      patches <- terra::patches(filtre_5, directions = 8, zeroAsNA = TRUE)
      vect_poly <- as.polygons(patches) |> st_as_sf()
      log("Vectorisation terminée —", nrow(vect_poly), "polygones créés")

      # === 2.4 Suppression polygones DN = 0 ===================================
      vect_poly <- vect_poly[vect_poly[[1]] != 0, ]

      # === 2.5 Filtre superficie < 10 m² ======================================
      vect_poly$superficie <- as.numeric(st_area(vect_poly))
      vect_poly <- vect_poly[vect_poly$superficie >= 10, ]
      log("Polygones après filtre superficie :", nrow(vect_poly))

      # === 2.6 Simplification et lissage ======================================
      st_crs(vect_poly) <- 2154
      vect_poly_wgs84 <- st_transform(vect_poly, crs = 4326)
      vect_poly_wgs84 <- ms_simplify(vect_poly_wgs84, keep = 0.4, keep_shapes = TRUE)
      vect_poly_wgs84 <- smooth(vect_poly_wgs84, method = "chaikin", refinements = 1)
      vect_poly <- st_transform(vect_poly_wgs84, crs = 2154)

      # === 2.7 Indices géométriques ===========================================
      vect_poly$superficie <- as.numeric(st_area(vect_poly))
      vect_poly$perimetre <- as.numeric(st_length(st_cast(st_geometry(vect_poly), "MULTILINESTRING")))
      vect_poly$convexite <- sapply(st_geometry(vect_poly), function(geom) {
        aire_poly <- as.numeric(st_area(geom))
        aire_convex <- as.numeric(st_area(st_convex_hull(geom)))
        if (aire_convex == 0) {
          return(NA)
        }
        aire_poly / aire_convex
      })

      # === 2.8 Pente moyenne et décile 10 =====================================
      log("Calcul des pentes...")
      mnt <- rast(fichier_mnt)
      pente <- terrain(mnt, v = "slope", unit = "degrees")
      pente_lissee <- focal(pente, w = 9, fun = "mean", na.rm = TRUE)

      vect_poly <- st_set_crs(vect_poly, 2154)
      vect_poly$pid <- seq_len(nrow(vect_poly))
      terra_poly <- vect(vect_poly)
      crs(pente_lissee) <- crs(terra_poly)
      poly_rast <- rasterize(terra_poly, pente_lissee, field = "pid")

      stats_moy <- zonal(pente_lissee, poly_rast, fun = "mean", na.rm = TRUE)
      names(stats_moy) <- c("pid", "pente_moyenne")
      vect_poly <- merge(vect_poly, stats_moy, by = "pid", all.x = TRUE)

      stats_dec <- zonal(pente_lissee, poly_rast, fun = function(x) quantile(x, probs = 0.1, na.rm = TRUE))
      names(stats_dec) <- c("pid", "pente_decile10")
      vect_poly <- merge(vect_poly, stats_dec, by = "pid", all.x = TRUE)
      vect_poly$pente_decile10 <- as.numeric(unlist(vect_poly$pente_decile10))

      vect_poly$pid <- NULL

      # === 2.9 Champs de diagnostic ===========================================
      vect_poly$diag_convexite <- ifelse(!is.na(vect_poly$convexite) & vect_poly$convexite >= 0.99, 1L, 0L)
      vect_poly$diag_pente_moy <- ifelse(is.na(vect_poly$pente_moyenne) | vect_poly$pente_moyenne < 7.5, 1L, 0L)
      vect_poly$diag_pente_dec10 <- ifelse(is.na(vect_poly$pente_decile10) | vect_poly$pente_decile10 < 45, 1L, 0L)

      # === 2.10 Sauvegarde ====================================================
      st_write(st_set_crs(vect_poly, 2154), fichier_out, delete_dsn = TRUE, quiet = TRUE)
      log("Sauvegardé →", fichier_out)

      return(list(dossier = nom_dossier, statut = "OK", n = nrow(vect_poly)))
    },
    error = function(e) {
      cat("[ERREUR]", nom_dossier, ":", conditionMessage(e), "\n")
      return(list(dossier = nom_dossier, statut = "ERREUR", message = conditionMessage(e)))
    }
  )
}

# ==============================================================================
# 3. LANCEMENT PARALLÈLE DU POST-TRAITEMENT
# ==============================================================================
cat("--- ÉTAPE 2 : Lancement du traitement parallèle ---\n")

n_cores <- max(1, detectCores() - 1)
cat("Lancement sur", n_cores, "cœurs pour", length(dossiers), "dossiers...\n\n")

cl <- makeCluster(n_cores)

clusterEvalQ(cl, {
  library(terra)
  library(sf)
  library(smoothr)
  library(rmapshaper)
})

resultats <- parLapply(cl, dossiers, traiter_dossier)

stopCluster(cl)

# ==============================================================================
# 4. BILAN DU TRAITEMENT
# ==============================================================================
cat("\n--- ÉTAPE 3 : Bilan du traitement ---\n")

for (res in resultats) {
  if (res$statut == "OK") {
    cat("  ✔", res$dossier, "—", res$n, "polygones\n")
  } else {
    cat("  ✘", res$dossier, "— ERREUR :", res$message, "\n")
  }
}

cat("\n--- PROCESSUS TERMINÉ AVEC SUCCÈS ---\n")
toc()
