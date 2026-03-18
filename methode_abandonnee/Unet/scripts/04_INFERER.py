# ==============================================================================
# SCRIPT PYTHON - INFÉRENCE U-NET
# ==============================================================================
# But : Appliquer le modèle U-Net entraîné sur de nouvelles images.
# Dépendances : os, json, glob, pandas, numpy, matplotlib, tensorflow, rasterio, skimage
# ==============================================================================

import os
import json
import glob

# Bibliothèques de manipulation de données
import pandas as pd
import numpy as np

# Bibliothèques de visualisation
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
from PIL import ImageColor

# Bibliothèques de machine learning
import tensorflow as tf
from tensorflow.keras.models import load_model

# Bibliothèques pour le traitement d'images et de données géospatiales
import rasterio
from rasterio.enums import Resampling
from skimage.exposure import rescale_intensity

# ==============================================================================
# 1. PARAMÈTRES ET CONFIGURATION
# ==============================================================================
print("--- ÉTAPE 1 : Chargement du modèle et configuration ---")

# --- Chargement du modèle ---
model_path = "chemin/vers/votre/dossier/data/MODEL_UNET.keras"
model = load_model(model_path)

# --- Création des dossiers de sortie ---
predicted_output_dir = "chemin/vers/votre/dossier/data/inference/SORTIE"
os.makedirs(predicted_output_dir, exist_ok=True)

patch_output_dir = "chemin/vers/votre/dossier/data/inference/patch_proba"
os.makedirs(patch_output_dir, exist_ok=True)

# --- Chargement du dossier contenant les images à traiter ---
input_folder = 'chemin/vers/votre/dossier/data/INFERENCE' 

# ==============================================================================
# 2. PRÉPARATION DE LA LÉGENDE
# ==============================================================================
print("--- ÉTAPE 2 : Chargement des métadonnées (Légende) ---")

# --- Chargement des paramètres de Land Cover et création de la colormap ---
lc_dir = 'chemin/vers/votre/dossier/lc.json'
lc = json.load(open(lc_dir))
lc_df = pd.DataFrame(lc)
lc_df["values_normalize"] = lc_df.index + 1
lc_df["palette"] = "#" + lc_df["palette"]

values = lc_df["values"].to_list()
values_norm = lc_df["values_normalize"].to_list()
palette = lc_df["palette"].to_list()
labels = lc_df["label"].to_list()
dict_values = {}
dict_label = {}
dict_palette = {}
dict_palette_hex = {}

for x in range(len(values)):
    dict_values[values[x]] = values_norm[x]
    dict_label[values_norm[x]] = labels[x]
    dict_palette[values_norm[x]] = ImageColor.getrgb(palette[x])
    dict_palette_hex[values_norm[x]] = palette[x]

# Création de la colormap pour matplotlib
cmap = ListedColormap(palette)

# ==============================================================================
# 3. DÉFINITION DE FONCTIONS COMMUNES
# ==============================================================================
overlap = 64
def extract_patches_with_overlap(image, patch_size=(128, 128), overlap=overlap):
    patches = []
    positions = []
    step = patch_size[0] - overlap
    for i in range(0, image.shape[0] - patch_size[0] + 1, step):
        for j in range(0, image.shape[1] - patch_size[1] + 1, step):
            patch = image[i:i + patch_size[0], j:j + patch_size[1], :]
            patches.append(patch)
            positions.append((i, j))
    return np.array(patches), positions

def create_weight_mask(patch_size):
    y = np.hanning(patch_size[0])
    x = np.hanning(patch_size[1])
    return np.outer(y, x)

# ==============================================================================
# 4. BOUCLE D'INFÉRENCE ET GÉNÉRATION DES PRÉDICTIONS
# ==============================================================================
print("--- ÉTAPE 3 : Lancement de l'inférence par tuile ---")

# --- Boucle d'inférence ---
tif_files = sorted(glob.glob(os.path.join(input_folder, "*.tif")))

n_classes = model.output_shape[-1]
patch_size = (128, 128)
weight_mask = create_weight_mask(patch_size)


selected_bands = [0, 1, 2, 3, 4, 5, 6, 7]


for idx, tif_path in enumerate(tif_files, start=1):
    print(f"\nTraitement de l'image {idx}: {tif_path}")
    with rasterio.open(tif_path) as source:
        # Lire TOUTES les bandes puis sélectionner
        all_bands = source.read().astype(np.float32)
        landsat_image = all_bands[selected_bands]  # SÉLECTION DES BANDES
        
        # ✅ CORRECTION : Remplacer les NaN par 0
        print(f"NaN détectés: {np.isnan(landsat_image).sum()} valeurs")
        landsat_image = np.nan_to_num(landsat_image, nan=0.0)
        
        # Normalisation IDENTIQUE à l'entraînement
        input_image = landsat_image.transpose(1, 2, 0)  # (H, W, C)
        
        # ✅ CORRECTION : Utiliser nanmax pour éviter les problèmes
        max_val = np.nanmax(input_image)
        if max_val == 0 or np.isnan(max_val):
            max_val = 1.0
        input_image = input_image / (max_val + 1e-8)
        
        print(f"Shape: {input_image.shape}, Min: {input_image.min():.4f}, Max: {input_image.max():.4f}")


        # Extract patches
        patches, positions = extract_patches_with_overlap(input_image, patch_size=patch_size, overlap=overlap)
        print(f"Nombre de patches extraits: {len(patches)}")

        weights_acc = np.zeros((source.height, source.width, n_classes), dtype=np.float32)
        prediction_image = np.zeros((source.height, source.width, n_classes), dtype=np.float32)

        total_patches = len(patches)
        processed_patches = 0
        skipped_band4 = 0
        
        for idx_patch, (patch, (i, j)) in enumerate(zip(patches, positions), start=1):
            # ✅ CORRECTION : Vérification stricte des NaN
            if np.isnan(patch).any() or np.isinf(patch).any():
                print(f"\rPatch {idx_patch}/{total_patches} SKIPPED (NaN/Inf)", end="")
                continue
            
            # ✅ CORRECTION : Vérification que le patch n'est pas vide
            if np.all(patch == 0):
                print(f"\rPatch {idx_patch}/{total_patches} SKIPPED (all zeros)", end="")
                continue
            
            # ✅ NOUVEAU : Ignorer si la bande 4 contient uniquement des 0
            band4_patch = patch[:, :, 4]  # La bande 4 est à l'index 4
            if np.all(band4_patch == 0):
                skipped_band4 += 1
                print(f"\rPatch {idx_patch}/{total_patches} SKIPPED (band 4 = 0)", end="")
                continue
                
            patch_input = np.expand_dims(patch, 0)
            pred = model.predict(patch_input, verbose=0)[0]
            processed_patches += 1

            # Enregistrement de la carte de probabilité pour le patch au format TIFF avec géoréférencement
            patch_filename = f"patch_proba_img{idx}_i{i}_j{j}.tif"
            patch_filepath = os.path.join(patch_output_dir, patch_filename)
            transform = source.transform * rasterio.Affine.translation(j, i)
            patch_meta = {
                'driver': 'GTiff',
                'height': patch_size[0],
                'width': patch_size[1],
                'count': n_classes,
                'dtype': 'float32',
                'crs': source.crs,
                'transform': transform
            }
            with rasterio.open(patch_filepath, 'w', **patch_meta) as dst:
                for b in range(n_classes):
                    dst.write(pred[..., b], b + 1)

            if pred.shape[-1] != n_classes:
                raise ValueError(f"Le modèle retourne {pred.shape[-1]} classes au lieu de {n_classes}.")

            # Fusion pondérée
            prediction_image[i:i + patch_size[0], j:j + patch_size[1], :] += pred * weight_mask[..., np.newaxis]
            weights_acc[i:i + patch_size[0], j:j + patch_size[1], :] += weight_mask[..., np.newaxis]

            print(f"\rPatch {idx_patch}/{total_patches} ({idx_patch/total_patches*100:.1f}%)", end="")


        # ✅ AFFICHER LES STATISTIQUES DE SKIP
        print(f"\n✅ Patches traités: {processed_patches}/{total_patches}")
        print(f"   - Skipped (band 4 = 0): {skipped_band4}")
        print(f"   - Skipped (autres raisons): {total_patches - processed_patches - skipped_band4}")
        
        # Normalisation correcte
        weights_sum = weights_acc.sum(axis=-1, keepdims=True)
        
        # Masque des pixels couverts
        mask_covered = (weights_sum[..., 0] > 0)
        print(f"Pixels couverts: {mask_covered.sum()} / {mask_covered.size} ({mask_covered.sum()/mask_covered.size*100:.1f}%)")
        
        # Division sécurisée
        weights_sum[weights_sum == 0] = 1
        prediction_image /= weights_sum
        
        # ✅ Vérification des probabilités
        print(f"Probabilités - Min: {prediction_image.min():.4f}, Max: {prediction_image.max():.4f}")
        print(f"Somme des probas par pixel (devrait être ~1.0): {prediction_image.sum(axis=-1).mean():.4f}")
        
        # Argmax
        final_pred = np.argmax(prediction_image, axis=-1).astype(np.uint8)
        
        # ✅ Mettre -1 pour les zones non couvertes
        final_pred[~mask_covered] = 255  # Valeur de NoData
        
        print("Valeurs uniques dans final_pred :", np.unique(final_pred, return_counts=True))


        # Écriture de l'image finale
        out_name = f"SORTIE_IMAGE_POUR_INF_{idx}.tif"
        out_path = os.path.join(predicted_output_dir, out_name)
        with rasterio.open(
            out_path, 'w', driver='GTiff',
            width=source.width,
            height=source.height,
            count=1,
            crs=source.crs,
            transform=source.transform,
            dtype='uint8',
            compress='lzw'
        ) as dst:
            dst.write(final_pred, 1)
            dst.write_colormap(1, dict_palette)

        print(f"Image prédite enregistrée sous: {out_path}")



    # --- Enregistrement de la carte de probabilité fusionnée ---
    proba_out_name = f"SORTIE_PROBA_FUSION_IMG_{idx}.tif"
    proba_out_path = os.path.join(predicted_output_dir, proba_out_name)

    with rasterio.open(
        proba_out_path, 'w',
        driver='GTiff',
        width=source.width,
        height=source.height,
        count=n_classes,
        dtype='float32',
        crs=source.crs,
        transform=source.transform,
        compress='lzw'
    ) as dst:
        for b in range(n_classes):
            dst.write(prediction_image[..., b], b + 1)

    print(f"Carte de probabilité fusionnée enregistrée sous: {proba_out_path}")

    total_images = len(tif_files)
    print(f"Image {idx}/{total_images} terminée ({idx/total_images*100:.1f}%)")

print("\nTraitement terminé pour l'ensemble des images.")

