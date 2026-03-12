# ==============================================================================
# SCRIPT PYQGIS - TERRASSES
# ==============================================================================
# But : Identifier les patchs de pente faible propices aux terrasses
# Version : 1.1 (compatible QGIS 3.4)
# Dépendances : processing
# ==============================================================================

import processing

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
# Chemins
WORKDIR = "chemin/vers/votre/dossier/data"
MNT = WORKDIR + "/entre/mnt.tif"

PENTE_FAIBLE_MAX = 15
PENTE_FORTE_MIN = 25

BUFFER_DISTANCE = 20
DENSITE_RAYON = 10
SURFACE_MIN = 5

# ==============================================================================
# 2. CALCUL DE LA PENTE
# ==============================================================================
print("--- ÉTAPE 1 : Calcul de la pente ---\n")

pente = processing.run(
    "gdal:slope",
    {
        'INPUT': MNT,
        'BAND': 1,
        'SCALE': 1,
        'AS_PERCENT': False,
        'COMPUTE_EDGES': True,
        'ZEVENBERGEN': False,
        'OUTPUT': WORKDIR + "/sortie/pente_deg_meth3.tif"
    }
)['OUTPUT']

# ==============================================================================
# 3. RECLASSIFICATION DES PENTES (RASTER CALCULATOR)
# ==============================================================================
print("--- ÉTAPE 2 : Reclassification des pentes ---\n")

# === 3.1 Pentes faibles =====================================================
pente_faible = processing.run(
    "qgis:rastercalculator",
    {
        'EXPRESSION': f'("{pente}@1" <= {PENTE_FAIBLE_MAX}) * 1',
        'LAYERS': [pente],
        'OUTPUT': WORKDIR + "/sortie/pente_faible_meth3.tif"
    }
)['OUTPUT']

# === 3.2 Pentes fortes ======================================================
pente_forte = processing.run(
    "qgis:rastercalculator",
    {
        'EXPRESSION': f'("{pente}@1" >= {PENTE_FORTE_MIN}) * 1',
        'LAYERS': [pente],
        'OUTPUT': WORKDIR + "/sortie/pente_forte_meth3.tif"
    }
)['OUTPUT']

# ==============================================================================
# 4. VECTORISATION DES PENTES FAIBLES
# ==============================================================================
print("--- ÉTAPE 3 : Vectorisation des pentes faibles ---\n")

patchs_faibles = processing.run(
    "gdal:polygonize",
    {
        'INPUT': pente_faible,
        'BAND': 1,
        'FIELD': 'value',
        'OUTPUT': WORKDIR + "/sortie/patchs_pente_faible_meth3.gpkg"
    }
)['OUTPUT']

# ==============================================================================
# 5. NETTOYAGE ET REPROJECTION DES PENTES FAIBLES
# ==============================================================================
print("--- ÉTAPE 4 : Nettoyage et reprojection des pentes faibles ---\n")

# === 5.1 Extraction des pentes faibles uniquement (value = 1) ===============
patchs_faibles_only = processing.run(
    "native:extractbyexpression",
    {
        'INPUT': patchs_faibles,
        'EXPRESSION': '"value" = 1',
        'OUTPUT': WORKDIR + "/sortie/patchs_pente_faible_only_meth3.gpkg"
    }
)['OUTPUT']

# === 5.2 Reprojection (EPSG:2154) ===========================================
patchs_faible_proj = processing.run(
    "native:reprojectlayer",
    {
        'INPUT': patchs_faibles_only,
        'TARGET_CRS': 'EPSG:2154',  # Lambert-93 (France, mètres)
        'OUTPUT': WORKDIR + "/sortie/patchs_faible_proj_meth3.gpkg"
    }
)['OUTPUT']

# === 5.3 Suppression des micro-patchs (SUR PENTES FAIBLES SEULEMENT) ========
patchs_faibles_net = processing.run(
    "native:extractbyexpression",
    {
        'INPUT': patchs_faible_proj,
        'EXPRESSION': f"$area >= {SURFACE_MIN}",
        'OUTPUT': WORKDIR + "/sortie/patchs_pente_faible_net_meth3.gpkg"
    }
)['OUTPUT']

# ==============================================================================
# 6. VECTORISATION DES PENTES FORTES
# ==============================================================================
print("--- ÉTAPE 5 : Vectorisation, nettoyage et reprojection des pentes fortes ---\n")

# === 6.1 Vectorisation ======================================================
pente_forte_vect = processing.run(
    "gdal:polygonize",
    {
        'INPUT': pente_forte,
        'BAND': 1,
        'FIELD': 'value',
        'OUTPUT': WORKDIR + "/sortie/pente_forte_meth3.gpkg"
    }
)['OUTPUT']

# === 6.2 Extraction des pentes fortes uniquement (value = 1) ================
patchs_forte_only = processing.run(
    "native:extractbyexpression",
    {
        'INPUT': pente_forte_vect,
        'EXPRESSION': '"value" = 1',
        'OUTPUT': WORKDIR + "/sortie/patchs_pente_forte_only_meth3.gpkg"
    }
)['OUTPUT']

# === 6.3 Reprojection (EPSG:2154) ===========================================
patchs_fort_proj = processing.run(
    "native:reprojectlayer",
    {
        'INPUT': patchs_forte_only,
        'TARGET_CRS': 'EPSG:2154',  # Lambert-93 (France, mètres)
        'OUTPUT': WORKDIR + "/sortie/patchs_fort_proj_meth3.gpkg"
    }
)['OUTPUT']

# ==============================================================================
# 7. BUFFER AUTOUR DES PENTES FORTES
# ==============================================================================
print(f"--- ÉTAPE 6 : Création du buffer de {BUFFER_DISTANCE}m autour des pentes fortes ---\n")

buffer_forte = processing.run(
    "native:buffer",
    {
        'INPUT': patchs_fort_proj,
        'DISTANCE': BUFFER_DISTANCE,
        'DISSOLVE': True,
        'OUTPUT': WORKDIR + "/sortie/buffer_pente_forte_meth3.gpkg"
    }
)['OUTPUT']

# ==============================================================================
# 8. PATCHS FAIBLES PROCHES DES PENTES FORTES
# ==============================================================================
print("--- ÉTAPE 7 : Sélection des patchs faibles dans le buffer ---\n")

patchs_proches = processing.run(
    "native:extractbylocation",
    {
        'INPUT': patchs_faibles_net,
        'PREDICATE': [0],  # intersect
        'INTERSECT': buffer_forte,
        'OUTPUT': WORKDIR + "/sortie/patchs_pente_faible_proches_meth3.gpkg"
    }
)['OUTPUT']

# ==============================================================================
# 9. DENSITÉ LOCALE DES PENTES FORTES
# ==============================================================================
print("--- ÉTAPE 8 : Calcul de la densité locale ---\n")

# Estimation de la taille de la fenêtre (en pixels)
taille = int((DENSITE_RAYON * 2) / 0.5)  # ~ résolution 0.5 m

# La taille DOIT être impaire (obligation mathématique)
if taille % 2 == 0:
    taille += 1

densite = processing.run(
    "grass7:r.neighbors",
    {
        'input': pente_forte,
        'method': 0,   # 0 = average (moyenne)
        'size': taille,
        'output': WORKDIR + "/sortie/densite_pente_forte_meth3.tif",
        'GRASS_REGION_PARAMETER': None,
        'GRASS_REGION_CELLSIZE_PARAMETER': 0,
        'GRASS_RASTER_FORMAT_OPT': '',
        'GRASS_RASTER_FORMAT_META': ''
    }
)['output']

# ==============================================================================
# 10. STATISTIQUES ZONALES ET SÉLECTION FINALE
# ==============================================================================
print("--- ÉTAPE 9 : Statistiques zonales et sélection des terrasses optimales ---\n")

processing.run(
    "qgis:zonalstatistics",
    {
        'INPUT_VECTOR': patchs_proches,
        'INPUT_RASTER': densite,
        'RASTER_BAND': 1,
        'COLUMN_PREFIX': 'dens_'
    }
)

patchs_optimaux = processing.run(
    "native:extractbyexpression",
    {
        'INPUT': patchs_proches,
        'EXPRESSION': '"dens_mean" >= 0.3 AND "dens_mean" <= 0.6',
        'OUTPUT': WORKDIR + "/sortie/patchs_terrasses_optimaux_meth3.gpkg"
    }
)['OUTPUT']

# ==============================================================================
# FIN DU SCRIPT
# ==============================================================================
print("--- PROCESSUS TERMINÉ AVEC SUCCÈS ---\n")
print(f"  [OK] Résultat final : {WORKDIR}/sortie/patchs_terrasses_optimaux_meth3.gpkg\n")