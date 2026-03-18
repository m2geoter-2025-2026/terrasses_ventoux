# ==============================================================================
# SCRIPT PYTHON - PRÉTRAITEMENT U-NET
# ==============================================================================
# But : Prétraiter les images Landsat et les masques de couverture terrestre, 
#       extraire des patches d'une taille spécifiée pour chaque classe,
#       et enregistrer les patches sous forme de fichiers GeoTIFF.
# Dépendances : os, json, numpy, pandas, rasterio, skimage, PIL
# ==============================================================================

import os
import json
import numpy as np
import pandas as pd
import rasterio as rio
from rasterio.enums import Resampling
from skimage import exposure
from PIL import ImageColor

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
# Définition de la position (gauche ou droite)
position = "droite" 

# Définition des chemins vers les fichiers et dossiers
lc_dir            = 'chemin/vers/votre/dossier/lc.json' 
lc_image_dir      = "chemin/vers/votre/dossier/data/IMAGE_MASQUE/MASQUE_" + position + ".tif"
landsat_dir       = "chemin/vers/votre/dossier/data/IMAGE_MASQUE/IMAGE_" + position + ".tif"
output_images_dir = 'chemin/vers/votre/dossier/data/images/'
output_lcs_dir    = 'chemin/vers/votre/dossier/data/lcs/'

# Paramètres de génération des patches
image_per_lc   = 0    # Paramètre du nombre de patchs  
suffixe_compte = 725  # Paramètre du suffixe du nom du fichier (mettre 0 ou image_per_lc)
patch_size     = 128

# Création des répertoires de sortie
os.makedirs(output_images_dir, exist_ok=True)
os.makedirs(output_lcs_dir, exist_ok=True)

# ==============================================================================
# 2. CHARGEMENT ET PRÉPARATION DE LA LÉGENDE
# ==============================================================================
print("--- ÉTAPE 1 : Import et préparation de la légende ---")

with open(lc_dir) as f:
    lc = json.load(f)

lc_df = pd.DataFrame(lc)
lc_df["values_normalize"] = lc_df.index + 1
lc_df["palette"] = "#" + lc_df["palette"]  

# Création des dictionnaires de mappage
dict_values = {v: k+1 for k, v in enumerate(lc_df["values"])}
dict_palette = {k+1: ImageColor.getrgb(v) for k, v in enumerate(lc_df["palette"])}

# ==============================================================================
# 3. CHARGEMENT ET PRÉTRAITEMENT DU MASQUE
# ==============================================================================
print("--- ÉTAPE 2 : Chargement et prétraitement du masque ---")

def mask_has_class_one(mask_array):
    """Retourne True si au moins un pixel == 2 dans le patch."""
    return np.any(mask_array == 2)

# Chargement et reclassement du masque
with rio.open(lc_image_dir) as src:
    lc_image = src.read(1)
    lc_image = np.vectorize(lambda x: dict_values.get(x, 0), otypes=[np.int32])(lc_image)

# Affichage informatif des classes
uniques = np.unique(lc_image[lc_image != 0])
print(f"Classes uniques présentes : {uniques}")

# ==============================================================================
# 4. CRÉATION DU COMPOSITE D'IMAGE SATELLITE
# ==============================================================================
print("--- ÉTAPE 3 : Création du composite ---")

with rio.open(landsat_dir) as landsat:
    landsat_image = landsat.read()
    
    # Calcul des min et max pour chaque bande (en ignorant les NaN)
    min_vals = np.nanmin(landsat_image, axis=(1, 2))
    max_vals = np.nanmax(landsat_image, axis=(1, 2))

    # Normalisation des bandes avec les min et max calculés
    composite = np.dstack([
        exposure.rescale_intensity(landsat_image[0], in_range=(min_vals[0], max_vals[0]), out_range=(0, 1)),
        exposure.rescale_intensity(landsat_image[1], in_range=(min_vals[1], max_vals[1]), out_range=(0, 1)),
        exposure.rescale_intensity(landsat_image[2], in_range=(min_vals[2], max_vals[2]), out_range=(0, 1)),
        exposure.rescale_intensity(landsat_image[3], in_range=(min_vals[3], max_vals[3]), out_range=(0, 1)),
        exposure.rescale_intensity(landsat_image[4], in_range=(min_vals[4], max_vals[4]), out_range=(0, 1)),
        exposure.rescale_intensity(landsat_image[5], in_range=(min_vals[5], max_vals[5]), out_range=(0, 1)),
        exposure.rescale_intensity(landsat_image[6], in_range=(min_vals[6], max_vals[6]), out_range=(0, 1)),
        exposure.rescale_intensity(landsat_image[7], in_range=(min_vals[7], max_vals[7]), out_range=(0, 1))
    ])

# ==============================================================================
# 5. GÉNÉRATION DES COORDONNÉES DES PATCHS
# ==============================================================================
print("--- ÉTAPE 4 : Génération des coordonnées des patches ---")

coords_list = []
height, width = lc_image.shape

for y in range(0, height - patch_size + 1, patch_size):
    for x in range(0, width - patch_size + 1, patch_size):

        mask_patch  = lc_image[y:y+patch_size, x:x+patch_size]
        image_patch = composite[y:y+patch_size, x:x+patch_size]

        # Vérifier présence de la classe voulue ET si les données sont valides
        if mask_has_class_one(mask_patch) and not np.any(np.isnan(image_patch)):
            coords_list.append((y, y+patch_size, x, x+patch_size))

print(f"Nombre total de patches valides identifiés : {len(coords_list)}")

# ==============================================================================
# 6. SAUVEGARDE DES PATCHES (IMAGES ET MASQUES)
# ==============================================================================
if len(coords_list) > 0:
    print("--- ÉTAPE 5 : Sauvegarde des patches (images) ---")

    with rio.open(landsat_dir) as landsat:
        for i, (min_y, max_y, min_x, max_x) in enumerate(coords_list, 1):
            image_patch = composite[min_y:max_y, min_x:max_x].transpose(2, 0, 1)

            with rio.open(
                os.path.join(output_images_dir, f'2_{i+suffixe_compte}_i.tif'),
                'w',
                driver='COG',
                height=patch_size,
                width=patch_size,
                count=8,
                dtype='float32',
                compress='LZW',
                crs=landsat.crs,
                transform=rio.windows.transform(
                    rio.windows.Window.from_slices((min_y, max_y), (min_x, max_x)),
                    landsat.transform
                )
            ) as dst:
                dst.write(image_patch)

    print("--- ÉTAPE 6 : Sauvegarde des patches (masques) ---")

    with rio.open(lc_image_dir) as src:
        for i, (min_y, max_y, min_x, max_x) in enumerate(coords_list, 1):
            mask_patch = lc_image[min_y:max_y, min_x:max_x].astype(np.uint8)

            with rio.open(
                os.path.join(output_lcs_dir, f'2_{i+suffixe_compte}_m.tif'),
                'w',
                driver='COG',
                height=patch_size,
                width=patch_size,
                count=1,
                dtype='uint8',
                compress='LZW',
                crs=src.crs,
                transform=rio.windows.transform(
                    rio.windows.Window.from_slices((min_y, max_y), (min_x, max_x)),
                    src.transform
                )
            ) as dst:
                dst.write(mask_patch, 1)
                # Ajout de la palette de couleur personnalisée
                dst.write_colormap(1, {k: tuple(v) for k, v in dict_palette.items()})

    print("--- PROCESSUS TERMINÉ AVEC SUCCÈS ---")
else:
    print("--- PROCESSUS TERMINÉ : Aucun patch valide trouvé ---")

# ==============================================================================
# 7. CODE ALTERNATIF / COMMENTÉ (GÉNÉRATION SANS CLASSE 2)
# ==============================================================================
"""
print("--- ÉTAPE OPTIONNELLE : Génération de patches sans classe 2 ---")

coords_no_class2 = []
max_attempts = 100000  # Pour éviter une boucle infinie
attempts = 0

while len(coords_no_class2) < 200 and attempts < max_attempts:
    attempts += 1
    
    y = np.random.randint(0, height - patch_size + 1)
    x = np.random.randint(0, width - patch_size + 1)
    
    mask_patch  = lc_image[y:y+patch_size, x:x+patch_size]
    image_patch = composite[y:y+patch_size, x:x+patch_size]
    
    # Vérifier PAS de classe 2 ET données valides
    if not np.any(mask_patch == 2) and not np.any(mask_patch == 0) and not np.any(np.isnan(image_patch)):
        coords_no_class2.append((y, y+patch_size, x, x+patch_size))

print(f"Patches sans classe 2 trouvés : {len(coords_no_class2)}")

# Sauvegarde des patches d'image sans classe 2
print("Sauvegarde des patches d'image sans classe 2")

with rio.open(landsat_dir) as landsat:
    for i, (min_y, max_y, min_x, max_x) in enumerate(coords_no_class2, 1):
        image_patch = composite[min_y:max_y, min_x:max_x].transpose(2, 0, 1)
        
        with rio.open(
            os.path.join(output_images_dir, f'1_{i+suffixe_compte}_i.tif'),
            'w', driver='COG', height=patch_size, width=patch_size,
            count=8, dtype='float32', compress='LZW', crs=landsat.crs,
            transform=rio.windows.transform(
                rio.windows.Window.from_slices((min_y, max_y), (min_x, max_x)),
                landsat.transform
            )
        ) as dst:
            dst.write(image_patch)

# Sauvegarde des patches de masque sans classe 2
print("Sauvegarde des patches de masque sans classe 2")

with rio.open(lc_image_dir) as src:
    for i, (min_y, max_y, min_x, max_x) in enumerate(coords_no_class2, 1):
        mask_patch = lc_image[min_y:max_y, min_x:max_x].astype(np.uint8)
        
        with rio.open(
            os.path.join(output_lcs_dir, f'1_{i+suffixe_compte}_m.tif'),
            'w', driver='COG', height=patch_size, width=patch_size,
            count=1, dtype='uint8', compress='LZW', crs=src.crs,
            transform=rio.windows.transform(
                rio.windows.Window.from_slices((min_y, max_y), (min_x, max_x)),
                src.transform
            )
        ) as dst:
            dst.write(mask_patch, 1)
            dst.write_colormap(1, {k: tuple(v) for k, v in dict_palette.items()})
"""
