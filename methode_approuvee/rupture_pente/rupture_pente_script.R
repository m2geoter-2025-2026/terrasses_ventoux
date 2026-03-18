# ==============================================================================
# SCRIPT R - RUPTURES DE PENTE (MSRM)
# ==============================================================================
# But : Pipeline de détection et tri des ruptures de pente (MSRM)
#       avec extraction morphologique et filtrage spatial.
# Dépendances : terra, tictoc
# ==============================================================================

# Neutraliser le conflit PROJ avec PostgreSQL/PostGIS AVANT de charger les libs
# (PostgreSQL installe une base proj.db incompatible qui prend le dessus)
Sys.unsetenv("PROJ_LIB")
Sys.unsetenv("PROJ_DATA")

if (!require("terra")) install.packages("terra", quiet = TRUE)
if (!require("tictoc")) install.packages("tictoc", quiet = TRUE)

library(terra)
library(tictoc)

crs_l93 <- "EPSG:2154"

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
# Chemins
path_mnt_entree <- "chemin/vers/votre/dossier/Rupture_pente/DATA/mnt.tif"
input_terrasses <- "chemin/vers/votre/dossier/Rupture_pente/DATA/TERRASSES.gpkg"
dossier_msrm_tri <- "chemin/vers/votre/dossier/Rupture_pente/Couche_qgis/MSRM_TRI"

# Création des répertoires de sortie
if (!dir.exists(dossier_msrm_tri)) dir.create(dossier_msrm_tri, recursive = TRUE, showWarnings = FALSE)

# Calcul du temps de début
temps_debut <- Sys.time()
cat("--- DÉBUT DE L'ANALYSE :", format(temps_debut, "%H:%M:%S"), "---\n\n")

# ==============================================================================
# 2. LECTURE DES DONNÉES D'ENTRÉE
# ==============================================================================
cat("--- ÉTAPE 1 : Lecture des données d'entrée ---\n")

mnt_full <- rast(path_mnt_entree)
terrasses <- vect(input_terrasses)

cat("  [OK] MNT       :", basename(path_mnt_entree), "\n")
cat("  [OK] Terrasses :", basename(input_terrasses), "\n\n")

# ==============================================================================
# 3. EXTRACTION MORPHOLOGIQUE (CRÉATION DU MSRM BRUT)
# ==============================================================================
cat("--- ÉTAPE 2 : Génération du MSRM brut ---\n")

cat("  Interpolation et calculs MSRM...\n")
grille_05 <- rast(extent = ext(mnt_full), res = 0.5, crs = crs(mnt_full))
mnt_sub <- resample(mnt_full, grille_05, method = "bilinear")

msrm_final <- ((mnt_sub - focal(mnt_sub, w = 3, fun = mean)) +
  (mnt_sub - focal(mnt_sub, w = 11, fun = mean)) +
  (mnt_sub - focal(mnt_sub, w = 21, fun = mean)) +
  (mnt_sub - focal(mnt_sub, w = 41, fun = mean))) / 4

cat("  Calcul des masques (pente, mur, replat, knickpoint)...\n")
pente <- terrain(mnt_sub, v = "slope", unit = "degrees")
masque_mur <- pente > 20
masque_replat <- pente < 7
replat_proximite <- focal(masque_replat, w = 13, fun = max)
knickpoint <- terrain(pente, v = "slope", unit = "degrees")
masque_knick <- knickpoint > 5

cat("  Extraction du MSRM brut...\n")
restanques_brut <- (msrm_final > 0.15) & masque_mur & replat_proximite & masque_knick
restanques_clean <- focal(restanques_brut, w = 3, fun = "modal")

cat("  Vectorisation...\n")
polys_msrm_brut <- as.polygons(restanques_clean, values = TRUE, digits = 0)
polys_msrm_brut <- polys_msrm_brut[polys_msrm_brut[[1]] == 1]
polys_msrm_brut <- disagg(polys_msrm_brut)

cat("  [OK] MSRM brut généré en mémoire\n\n")

# ==============================================================================
# 4. TRI SPATIAL ANALYTIQUE (FILTRAGE AVEC LES TERRASSES)
# ==============================================================================
cat("--- ÉTAPE 3 : Filtrage spatial avec les terrasses ---\n")

# Harmonisation des couches
set.crs(polys_msrm_brut, crs_l93)
set.crs(terrasses, crs_l93)

cat("  Remplissage des polygones...\n")
restanques_remplies <- fillHoles(polys_msrm_brut)
restanques_remplies <- makeValid(restanques_remplies)
terrasses <- makeValid(terrasses)

cat("  [OK] Polygones prêts pour la soustraction\n\n")

# ==============================================================================
# 5. SOUSTRACTION GÉOMÉTRIQUE (ERASE)
# ==============================================================================
cat("--- ÉTAPE 4 : Soustraction géométrique (Erase) ---\n")
cat("  Début de la soustraction à :", format(Sys.time(), "%H:%M:%S"), "\n")

tic("  Durée de la soustraction")
restanques_finales <- erase(restanques_remplies, terrasses)
toc()

cat("  [OK] Soustraction terminée à :", format(Sys.time(), "%H:%M:%S"), "\n\n")

# ==============================================================================
# 6. NETTOYAGE ET EXPORTATION FINALE
# ==============================================================================
cat("--- ÉTAPE 5 : Nettoyage et exportation finale ---\n")

cat("  Disagrégation et calcul des surfaces...\n")
restanques_finales <- disagg(restanques_finales)
restanques_finales <- makeValid(restanques_finales)
restanques_finales$area_final_m2 <- expanse(restanques_finales)

cat("  Filtrage des surfaces >= 3 m²...\n")
restanques_finales <- restanques_finales[restanques_finales$area_final_m2 >= 3]

if (nrow(restanques_finales) > 0) {
  chemin_final <- file.path(dossier_msrm_tri, "Ruptures_Pente_HORS_Terrasses.gpkg")
  writeVector(restanques_finales, chemin_final, overwrite = TRUE)
  cat("  [OK] Résultat final exporté :", basename(chemin_final), "\n")
} else {
  cat("  [!] Aucun polygone restant après filtrage.\n")
}
cat("\n")

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
