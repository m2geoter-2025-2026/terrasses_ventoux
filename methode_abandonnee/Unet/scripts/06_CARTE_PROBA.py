# ==============================================================================
# SCRIPT PYTHON - CARTE DE PROBABILITÉ
# ==============================================================================
# But : Fusionner les patches de probabilités générés lors de l'inférence.
# Dépendances : os, glob, numpy, rasterio
# ==============================================================================

import os
import glob
import numpy as np
import rasterio
from rasterio.transform import Affine

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
patch_dir = r"chemin/vers/votre/dossier/data/inference/patch_proba"
output_path = r"chemin/vers/votre/dossier/data/inference/CARTE_PROBA.tif"

# ==============================================================================
# 2. FUSION DES PROBABILITÉS
# ==============================================================================
print("--- ÉTAPE 1 : Configuration et lecture des fichiers ---")

# S'assurer que le répertoire de sortie existe
patch_files = sorted(glob.glob(os.path.join(patch_dir, "*.tif")))
if not patch_files:
    raise FileNotFoundError(f"No .tif files found in {patch_dir}")

# Lire les métadonnées du premier patch pour initialiser le mosaic
with rasterio.open(patch_files[0]) as src0:
    meta = src0.meta.copy()
    patch_height = src0.height
    patch_width = src0.width
    res_x = src0.transform.a
    res_y = -src0.transform.e
    orig_transform = src0.transform

# Créer une fenêtre de Hann 
y = np.hanning(patch_height)
x = np.hanning(patch_width)
hann_window = np.outer(y, x)

# Calculer les limites globales de tous les patches
bounds = []
for f in patch_files:
    with rasterio.open(f) as src:
        bounds.append(src.bounds)

min_x = min(b.left for b in bounds)
max_x = max(b.right for b in bounds)
min_y = min(b.bottom for b in bounds)
max_y = max(b.top for b in bounds)

# Calculer la taille totale du mosaic
total_width = int(np.ceil((max_x - min_x) / res_x))
total_height = int(np.ceil((max_y - min_y) / res_y))

# Initialiser l'accumulateur et la somme des poids
accumulator = np.zeros((total_height, total_width), dtype=np.float32)
weight_sum  = np.zeros((total_height, total_width), dtype=np.float32)

# Parcourir chaque patch pour le fusionner dans le mosaic
for f in patch_files:
    with rasterio.open(f) as src:
        # Lire les données du patch
        data = src.read()  
        max_prob = np.max(data, axis=0)

        # Calculer les offsets pour placer le patch dans le mosaic
        b = src.bounds
        col_off = int(round((b.left - min_x) / res_x))
        row_off = int(round((max_y - b.top) / res_y))

        # Vérifier les dimensions du patch
        accumulator[row_off:row_off + patch_height,
                    col_off:col_off + patch_width] += max_prob * hann_window
        weight_sum[row_off:row_off + patch_height,
                   col_off:col_off + patch_width] += hann_window

# Éviter la division par zéro
mask = weight_sum == 0
weight_sum[mask] = 1.0

# Calculer la moyenne pondérée
dst_array = accumulator / weight_sum

# Préparer les métadonnées pour le mosaic
dst_meta = meta.copy()
dst_meta.update({
    "driver": "GTiff",
    "height": total_height,
    "width": total_width,
    "count": 1,
    "dtype": "float32",
    "transform": Affine(res_x, 0, min_x,
                          0, -res_y, max_y)
})

# Enregistrer le mosaic dans un fichier
with rasterio.open(output_path, 'w', **dst_meta) as dst:
    dst.write(dst_array, 1)

print(f"Mosaic saved to {output_path}")
