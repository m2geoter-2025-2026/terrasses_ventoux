# ==============================================================================
# SCRIPT R - POST-TRAITEMENT GEOBIA (TERRASSES)
# ==============================================================================
# Auteur : M2 GEOTER
# But : Filtrage expert de segments d'images pour identifier des restanques
#       en se basant sur des indices topographiques (Pente, Exposition, TPI).
# Dépendances : librairie 'terra'
# ==============================================================================

library(terra)

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
# Définition des chemins vers les fichiers d'entrée (Segmentation et MNT) et de sortie.
path_seg    <- "chemin/vers/votre/dossier/raster_emprise.tif" # Raster de votre emprise
path_mnt_lg <- "chemin/vers/votre/dossier/mnt_zone.tif" # MNT de la zone étudiée 
output_dir  <- "chemin/vers/votre/dossier/sortie/" # Dossier de sortie 

print("--- ÉTAPE 1 : Chargement et Découpage ---")
r_seg <- rast(path_seg)
mnt_large <- rast(path_mnt_lg)

# ==============================================================================
# 2. CHARGEMENT ET PRÉPARATION DES DONNÉES
# ==============================================================================
# Découpage du MNT sur l'emprise exacte du raster segmenté pour gagner du temps
mnt <- crop(mnt_large, r_seg)
mnt <- resample(mnt, r_seg, method="bilinear")

# Nettoyage de la mémoire vive
rm(mnt_large)
gc()
print(r_seg)
plot(r_seg, col = sample(rainbow(255)))

# ==============================================================================
# 3. CALCUL DES INDICES TOPOGRAPHIQUES
# ==============================================================================
print("--- ÉTAPE 2 : Calcul des indices (Pente, Aspect, TPI) ---")
pente      <- terrain(mnt, v="slope", unit="degrees")
exposition <- terrain(mnt, v="aspect", unit="degrees")

# TPI (Topographic Position Index) optimisé avec matrice de poids
fw  <- matrix(1, nrow=9, ncol=9)
tpi <- mnt - focal(mnt, w=fw, fun="mean") 

# ==============================================================================
# 4. STATISTIQUES ZONALES PAR SEGMENT
# ==============================================================================
print("--- ÉTAPE 3 : Statistiques par segment ---")
stats_pente <- zonal(pente, r_seg, fun="mean", na.rm=TRUE)
stats_expo  <- zonal(exposition, r_seg, fun="mean", na.rm=TRUE)
stats_tpi   <- zonal(tpi, r_seg, fun="mean", na.rm=TRUE)

# Calcul de la surface (nombre de pixels) pour éliminer les polygones massifs
v_pixels <- values(r_seg)
tab_area <- as.data.frame(table(v_pixels))
colnames(tab_area) <- c("ID", "pixel_count")
tab_area$ID <- as.numeric(as.character(tab_area$ID))

# Harmonisation des noms de colonnes pour la fusion
colnames(stats_pente) <- c("ID", "pente_moy")
colnames(stats_expo)  <- c("ID", "expo_moy")
colnames(stats_tpi)   <- c("ID", "tpi_moy")

# ==============================================================================
# 5. FUSION ET FILTRAGE EXPERT
# ==============================================================================
print("--- ÉTAPE 4 : Filtrage des restanques ---")
# Regroupement de toutes les statistiques dans un seul tableau
final_stats <- merge(stats_pente, stats_expo, by="ID")
final_stats <- merge(final_stats, stats_tpi, by="ID")
final_stats <- merge(final_stats, tab_area, by="ID")

# Affichage d'un aperçu pour vérifier que tout est chargé
print(head(final_stats))

# CRITÈRES AFFINÉS POUR L'IDENTIFICATION DES RESTANQUES :
# - Pente entre 4° et 16° (on évite le plat des vallées < 4°)
# - Exposition Sud (130° à 240°)
# - TPI > 0.05 (rupture de pente positive)
# - Taille < 2000 pixels (évite les grands champs ou grandes forêts)
ids_restanques <- final_stats$ID[
  final_stats$pente_moy > 4 & final_stats$pente_moy < 16 &
    final_stats$expo_moy > 130 & final_stats$expo_moy < 240 &
    final_stats$tpi_moy > 0.05 & final_stats$tpi_moy < 0.7 & 
    final_stats$pixel_count > 5 & final_stats$pixel_count < 2000
]

# ==============================================================================
# 6. CRÉATION DU RASTER ET EXPORT
# ==============================================================================
if(length(ids_restanques) > 0) {
  print(paste("Succès :", length(ids_restanques), "segments identifiés."))
  
  # Méthode de masquage ultra-rapide pour isoler les segments valides
  mask <- r_seg %in% ids_restanques
  restanques_raster <- classify(mask, matrix(c(0, NA), ncol=2))
  
  # Export Raster 
  writeRaster(restanques_raster, paste0(output_dir, "dossier_sortie.tif"), 
              overwrite=TRUE, datatype='INT1U', gdal=c("COMPRESS=DEFLATE"))
  
  print("--- PROCESSUS TERMINÉ ---")
  print(paste("Fichier disponible ici :", paste0(output_dir, "dossier_sortie.tif")))
  print("CONSEIL : Ouvrez ce .tif dans QGIS et utilisez l'outil 'Polygoniser' pour le transformer en vecteur.")
} else {
  print("ERREUR : Aucun segment trouvé avec ces critères. Essayez d'élargir les seuils (ex: pente > 2).")
}