# ==============================================================================
# SCRIPT PYQGIS - TERRASSES - TEST SENSIBILITÉ BUFFER
# ==============================================================================
# 
# But : Analyse scientifique du paramètre BUFFER_DISTANCE
# Version : V8B
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

# Pentes fixées (choix validé)
PENTE_FAIBLE_MAX = 15
PENTE_FORTE_MIN = 25

DENSITE_RAYON = 10
SURFACE_MIN = 5

BUFFER_LIST = [5, 10, 15]

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
        'OUTPUT': WORKDIR + "/sortie/pente_buffer_test_v8b.tif"
    }
)['OUTPUT']

# ==============================================================================
# 3. RECLASSIFICATION
# ==============================================================================
print("--- ÉTAPE 2 : Reclassification ---\n")

pente_faible = processing.run(
    "qgis:rastercalculator",
    {
        'EXPRESSION': f'if("{pente}@1" <= {PENTE_FAIBLE_MAX}, 1, 0)',
        'LAYERS': [pente],
        'OUTPUT': WORKDIR + "/sortie/pente_faible_buffer_test_v8b.tif"
    }
)['OUTPUT']

pente_forte = processing.run(
    "qgis:rastercalculator",
    {
        'EXPRESSION': f'if("{pente}@1" >= {PENTE_FORTE_MIN}, 1, 0)',
        'LAYERS': [pente],
        'OUTPUT': WORKDIR + "/sortie/pente_forte_buffer_test_v8b.tif"
    }
)['OUTPUT']

# ==============================================================================
# 4. VECTORISATION PENTES FAIBLES
# ==============================================================================
print("--- ÉTAPE 3 : Vectorisation pentes faibles ---\n")

patchs_faibles = processing.run(
    "gdal:polygonize",
    {
        'INPUT': pente_faible,
        'BAND': 1,
        'FIELD': 'value',
        'OUTPUT': WORKDIR + "/sortie/patchs_faible_buffer_test_v8b.gpkg"
    }
)['OUTPUT']

patchs_faibles = processing.run(
    "native:extractbyexpression",
    {
        'INPUT': patchs_faibles,
        'EXPRESSION': '"value" = 1',
        'OUTPUT': WORKDIR + "/sortie/patchs_faible_only_buffer_test_v8b.gpkg"
    }
)['OUTPUT']

patchs_faibles = processing.run(
    "native:reprojectlayer",
    {
        'INPUT': patchs_faibles,
        'TARGET_CRS': 'EPSG:2154',
        'OUTPUT': WORKDIR + "/sortie/patchs_faible_proj_buffer_test_v8b.gpkg"
    }
)['OUTPUT']

patchs_faibles = processing.run(
    "native:fieldcalculator",
    {
        'INPUT': patchs_faibles,
        'FIELD_NAME': 'area_m2',
        'FIELD_TYPE': 0,
        'FIELD_LENGTH': 20,
        'FIELD_PRECISION': 2,
        'NEW_FIELD': True,
        'FORMULA': 'area($geometry)',
        'OUTPUT': WORKDIR + "/sortie/patchs_faible_area_buffer_test_v8b.gpkg"
    }
)['OUTPUT']

patchs_faibles = processing.run(
    "native:extractbyexpression",
    {
        'INPUT': patchs_faibles,
        'EXPRESSION': f'"area_m2" >= {SURFACE_MIN}',
        'OUTPUT': WORKDIR + "/sortie/patchs_faible_filtre_buffer_test_v8b.gpkg"
    }
)['OUTPUT']

# ==============================================================================
# 5. VECTORISATION PENTES FORTES
# ==============================================================================
print("--- ÉTAPE 4 : Vectorisation pentes fortes ---\n")

patchs_forte = processing.run(
    "gdal:polygonize",
    {
        'INPUT': pente_forte,
        'BAND': 1,
        'FIELD': 'value',
        'OUTPUT': WORKDIR + "/sortie/patchs_forte_buffer_test_v8b.gpkg"
    }
)['OUTPUT']

patchs_forte = processing.run(
    "native:extractbyexpression",
    {
        'INPUT': patchs_forte,
        'EXPRESSION': '"value" = 1',
        'OUTPUT': WORKDIR + "/sortie/patchs_forte_only_buffer_test_v8b.gpkg"
    }
)['OUTPUT']

patchs_forte = processing.run(
    "native:reprojectlayer",
    {
        'INPUT': patchs_forte,
        'TARGET_CRS': 'EPSG:2154',
        'OUTPUT': WORKDIR + "/sortie/patchs_forte_proj_buffer_test_v8b.gpkg"
    }
)['OUTPUT']

# ==============================================================================
# 6. TESTS BUFFER
# ==============================================================================
print("--- ÉTAPE 5 : Tests buffer ---\n")

for BUFFER_DISTANCE in BUFFER_LIST:

    print(f"--- Traitement BUFFER = {BUFFER_DISTANCE} ---")

    buffer_forte = processing.run(
        "native:buffer",
        {
            'INPUT': patchs_forte,
            'DISTANCE': BUFFER_DISTANCE,
            'DISSOLVE': True,
            'OUTPUT': WORKDIR + f"/sortie/buffer_pente_forte_buffer_test_{BUFFER_DISTANCE}_v8b.gpkg"
        }
    )['OUTPUT']

    patchs_proches = processing.run(
        "native:extractbylocation",
    {
            'INPUT': patchs_faibles,
            'PREDICATE': [0],
            'INTERSECT': buffer_forte,
            'OUTPUT': WORKDIR + f"/sortie/patchs_proches_buffer_test_{BUFFER_DISTANCE}_v8b.gpkg"
        }
    )['OUTPUT']

    # === 6.1 Densité locale =====================================================

    taille = int((DENSITE_RAYON * 2) / 0.5)
    if taille % 2 == 0:
        taille += 1

    densite = processing.run(
        "grass7:r.neighbors",
        {
            'input': pente_forte,
            'method': 0,
            'size': taille,
            'output': WORKDIR + f"/sortie/densite_buffer_test_{BUFFER_DISTANCE}_v8b.tif",
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

    patchs_final = processing.run(
        "native:extractbyexpression",
        {
            'INPUT': patchs_proches,
            'EXPRESSION': '"dens_mean" >= 0.3 AND "dens_mean" <= 0.6',
            'OUTPUT': WORKDIR + f"/sortie/patchs_terrasses_optimaux_buffer_test_{BUFFER_DISTANCE}_v8b.gpkg"
        }
    )['OUTPUT']

    layer = QgsVectorLayer(patchs_final, "", "ogr")
    total_area = sum(f.geometry().area() for f in layer.getFeatures())

    print("  [OK] Surface finale (m²) :", round(total_area, 2), "\n")

    results.append({
        "buffer": BUFFER_DISTANCE,
        "area_m2": total_area,
        "path": patchs_final
    })

# ==============================================================================
# 7. ANALYSE JACCARD
# ==============================================================================
print("--- ÉTAPE 6 : Analyse de stabilité (Jaccard) ---\n")

for i in range(len(results)):
    for j in range(i + 1, len(results)):

        layerA = QgsVectorLayer(results[i]["path"], "", "ogr")
        layerB = QgsVectorLayer(results[j]["path"], "", "ogr")

        inter = processing.run(
            "native:intersection",
            {
                'INPUT': layerA,
                'OVERLAY': layerB,
                'OUTPUT': WORKDIR + f"/sortie/inter_buffer_test_{results[i]['buffer']}_{results[j]['buffer']}_v8b.gpkg"
            }
        )['OUTPUT']

        inter_layer = QgsVectorLayer(inter, "", "ogr")
        inter_area = sum(f.geometry().area() for f in inter_layer.getFeatures())

        union_area = results[i]["area_m2"] + results[j]["area_m2"] - inter_area
        jaccard = inter_area / union_area if union_area != 0 else 0

        print(f"  Comparaison {results[i]['buffer']} vs {results[j]['buffer']} → Jaccard = {round(jaccard, 3)}")

print("\n--- PROCESSUS TERMINÉ AVEC SUCCÈS ---")
print("Script V8B terminé sans écraser les résultats précédents.\n")