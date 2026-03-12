# ==============================================================================
# SCRIPT PYQGIS - TERRASSES - ANALYSE DE SENSIBILITÉ (PENTES)
# ==============================================================================
# But : Identifier les patchs de pente faible propices aux terrasses
#       + Analyse de sensibilité des seuils (Indice de Jaccard)
# Version : 7 corrigée (area sécurisée, fix inutile supprimé)
# Compatible QGIS 3.4
# Dépendances : os, processing, qgis.core
# ==============================================================================

import os
import processing
from qgis.core import QgsVectorLayer

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
# Chemins
WORKDIR = "chemin/vers/votre/dossier/data"
MNT = WORKDIR + "/entre/mnt.tif"

PENTE_FAIBLE_LIST = [10, 15, 20]
PENTE_FORTE_LIST = [25, 30, 35]

BUFFER_DISTANCE = 10
DENSITE_RAYON = 10
SURFACE_MIN = 5

results = []

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
        'OUTPUT': WORKDIR + "/sortie/pente_ezequart.tif"
    }
)['OUTPUT']

# ==============================================================================
# 3. BOUCLE DES TESTS
# ==============================================================================
print("--- ÉTAPE 2 : Boucle des tests (Pentes faibles / Pentes fortes) ---\n")

for PENTE_FAIBLE_MAX in PENTE_FAIBLE_LIST:
    for PENTE_FORTE_MIN in PENTE_FORTE_LIST:

        if PENTE_FAIBLE_MAX >= PENTE_FORTE_MIN:
            continue

        test_name = f"{PENTE_FAIBLE_MAX}_{PENTE_FORTE_MIN}"
        print(f"--- Traitement Test : {test_name} ---")

        # === 3.1 Reclassification corrigée ==========================================
        pente_faible = processing.run(
            "qgis:rastercalculator",
            {
                'EXPRESSION': f'if("{pente}@1" <= {PENTE_FAIBLE_MAX}, 1, 0)',
                'LAYERS': [pente],
                'OUTPUT': WORKDIR + f"/sortie/pente_faible_ezequart_{test_name}.tif"
            }
        )['OUTPUT']

        pente_forte = processing.run(
            "qgis:rastercalculator",
            {
                'EXPRESSION': f'if("{pente}@1" >= {PENTE_FORTE_MIN}, 1, 0)',
                'LAYERS': [pente],
                'OUTPUT': WORKDIR + f"/sortie/pente_forte_ezequart_{test_name}.tif"
            }
        )['OUTPUT']

        # === 3.2 Vectorisation pentes faibles =======================================
        patchs_faibles = processing.run(
            "gdal:polygonize",
            {
                'INPUT': pente_faible,
                'BAND': 1,
                'FIELD': 'value',
                'OUTPUT': WORKDIR + f"/sortie/patchs_pente_faible_ezequart_{test_name}.gpkg"
            }
        )['OUTPUT']

        patchs_faibles_only = processing.run(
            "native:extractbyexpression",
            {
                'INPUT': patchs_faibles,
                'EXPRESSION': '"value" = 1',
                'OUTPUT': WORKDIR + f"/sortie/patchs_pente_faible_only_ezequart_{test_name}.gpkg"
            }
        )['OUTPUT']

        patchs_faible_proj = processing.run(
            "native:reprojectlayer",
            {
                'INPUT': patchs_faibles_only,
                'TARGET_CRS': 'EPSG:2154',
                'OUTPUT': WORKDIR + f"/sortie/patchs_faible_proj_ezequart_{test_name}.gpkg"
            }
        )['OUTPUT']

        # === 3.3 Ajout champ surface ================================================
        patchs_faibles_net = processing.run(
            "native:fieldcalculator",
            {
                'INPUT': patchs_faible_proj,
                'FIELD_NAME': 'area_m2',
                'FIELD_TYPE': 0,  # Decimal
                'FIELD_LENGTH': 20,
                'FIELD_PRECISION': 2,
                'NEW_FIELD': True,
                'FORMULA': 'area($geometry)',
                'OUTPUT': WORKDIR + f"/sortie/patchs_pente_faible_net_ezequart_{test_name}.gpkg"
            }
        )['OUTPUT']

        # === 3.4 Filtrage par surface min ===========================================
        patchs_faibles_net = processing.run(
            "native:extractbyexpression",
            {
                'INPUT': patchs_faibles_net,
                'EXPRESSION': f"\"area_m2\" >= {SURFACE_MIN}",
                'OUTPUT': WORKDIR + f"/sortie/patchs_pente_faible_filtre_ezequart_{test_name}.gpkg"
            }
        )['OUTPUT']

        # === 3.5 Vectorisation pentes fortes ========================================
        pente_forte_vect = processing.run(
            "gdal:polygonize",
            {
                'INPUT': pente_forte,
                'BAND': 1,
                'FIELD': 'value',
                'OUTPUT': WORKDIR + f"/sortie/pente_forte_vect_ezequart_{test_name}.gpkg"
            }
        )['OUTPUT']

        patchs_forte_only = processing.run(
            "native:extractbyexpression",
            {
                'INPUT': pente_forte_vect,
                'EXPRESSION': '"value" = 1',
                'OUTPUT': WORKDIR + f"/sortie/patchs_pente_forte_only_ezequart_{test_name}.gpkg"
            }
        )['OUTPUT']

        patchs_fort_proj = processing.run(
            "native:reprojectlayer",
            {
                'INPUT': patchs_forte_only,
                'TARGET_CRS': 'EPSG:2154',
                'OUTPUT': WORKDIR + f"/sortie/patchs_fort_proj_ezequart_{test_name}.gpkg"
            }
        )['OUTPUT']

        # === 3.6 Buffer pentes fortes ===============================================
        buffer_forte = processing.run(
            "native:buffer",
            {
                'INPUT': patchs_fort_proj,
                'DISTANCE': BUFFER_DISTANCE,
                'DISSOLVE': True,
                'OUTPUT': WORKDIR + f"/sortie/buffer_pente_forte_ezequart_{test_name}.gpkg"
            }
        )['OUTPUT']

        # === 3.7 Patchs faibles proches =============================================
        patchs_proches = processing.run(
            "native:extractbylocation",
            {
                'INPUT': patchs_faibles_net,
                'PREDICATE': [0],
                'INTERSECT': buffer_forte,
                'OUTPUT': WORKDIR + f"/sortie/patchs_pente_faible_proches_ezequart_{test_name}.gpkg"
            }
        )['OUTPUT']

        # === 3.8 Densite locale =====================================================
        taille = int((DENSITE_RAYON * 2) / 0.5)
        if taille % 2 == 0:
            taille += 1

        densite = processing.run(
            "grass7:r.neighbors",
            {
                'input': pente_forte,
                'method': 0,
                'size': taille,
                'output': WORKDIR + f"/sortie/densite_ezequart_{test_name}.tif",
                'GRASS_REGION_PARAMETER': None,
                'GRASS_REGION_CELLSIZE_PARAMETER': 0,
                'GRASS_RASTER_FORMAT_OPT': '',
                'GRASS_RASTER_FORMAT_META': ''
            }
        )['output']

        processing.run(
            "qgis:zonalstatistics",
            {
                'INPUT_VECTOR': patchs_proches,
                'INPUT_RASTER': densite,
                'RASTER_BAND': 1,
                'COLUMN_PREFIX': 'dens_'
            }
        )

        # === 3.9 Selection finale ===================================================
        patchs_optimaux = processing.run(
            "native:extractbyexpression",
            {
                'INPUT': patchs_proches,
                'EXPRESSION': '"dens_mean" >= 0.3 AND "dens_mean" <= 0.6',
                'OUTPUT': WORKDIR + f"/sortie/patchs_terrasses_optimaux_ezequart_{test_name}.gpkg"
            }
        )['OUTPUT']

        layer = QgsVectorLayer(patchs_optimaux, "", "ogr")
        if not layer.isValid():
            continue

        total_area = sum(f.geometry().area() for f in layer.getFeatures())

        print("  [OK] Surface finale (m²) :", round(total_area, 2), "\n")

        results.append({
            "pf": PENTE_FAIBLE_MAX,
            "pF": PENTE_FORTE_MIN,
            "area_m2": total_area,
            "path": patchs_optimaux
        })

# ==============================================================================
# 4. ANALYSE JACCARD SÉCURISÉE
# ==============================================================================
print("--- ÉTAPE 3 : Analyse de stabilité (Jaccard) ---\n")

for i in range(len(results)):
    for j in range(i + 1, len(results)):

        pf1 = results[i]["pf"]
        pF1 = results[i]["pF"]
        pf2 = results[j]["pf"]
        pF2 = results[j]["pF"]

        if (pf1 == pf2 and pF1 != pF2) or (pf1 != pf2 and pF1 == pF2):

            layerA = QgsVectorLayer(results[i]["path"], "", "ogr")
            layerB = QgsVectorLayer(results[j]["path"], "", "ogr")

            inter = processing.run(
                "native:intersection",
                {
                    'INPUT': layerA,
                    'OVERLAY': layerB,
                    'OUTPUT': WORKDIR + f"/sortie/interezequart_{pf1}_{pF1}_vs_{pf2}_{pF2}.gpkg"
                }
            )['OUTPUT']

            inter_layer = QgsVectorLayer(inter, "", "ogr")
            inter_area = sum(f.geometry().area() for f in inter_layer.getFeatures())

            union_area = results[i]["area_m2"] + results[j]["area_m2"] - inter_area
            jaccard = inter_area / union_area if union_area != 0 else 0

            print(f"  Comparaison {pf1}/{pF1} vs {pf2}/{pF2} → Jaccard = {round(jaccard, 3)}")

print("\n--- PROCESSUS TERMINÉ AVEC SUCCÈS ---")
