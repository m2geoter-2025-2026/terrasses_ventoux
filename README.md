# Terrasses Ventoux

Ce dépôt regroupe les scripts de cartographie et de détection des terrasses agricoles sur le Mont Ventoux, développés dans le cadre du Master 2 GEOTER (2025-2026).

## Données

Les données associées à ce projet sont archivées et accessibles via Zenodo :

[https://zenodo.org/records/18983835](https://zenodo.org/records/18983835)

## Structure du dépôt

```
.
├── GEOBIA/                  # Approche orientée objet (GEOBIA)
│   └── Geobia.R
│
├── randomforest/            # Chaîne de traitement Random Forest
│   ├── 01_DECOUPE_IMAGES_DOSSIERS.R
│   ├── 02_INFERENCE_RANDOM_FOREST.R
│   ├── 03_FUSIONNER_RASTER.R
│   ├── 04_SEUILS.R
│   ├── 05_POST_TRAITEMENTS.R
│   └── 06_FUSION.R
│
├── Unet/                    # Chaîne de traitement U-Net (apprentissage profond)
│   ├── modele/
│   │   └── best_model.keras
│   └── scripts/
│       ├── 01_PREPROCESSER.py
│       ├── 02_ENTRAINER.ipynb
│       ├── 03_DECOUPER_SOUS_ENSEMBLE.py
│       ├── 04_INFERER.py
│       ├── 05_FUSIONNER_SOUS_ENSEMBLE.py
│       └── 06_CARTE_PROBA.py
│
├── eco_paysage/             # Analyse de métriques paysagères
│   └── ecopaysage.py
│
└── lien_donnees_zenodo.txt  # Référence aux données sur Zenodo
```

## Approches de cartographie

### Random Forest (`randomforest/`)

Chaîne de traitement complète en R pour la détection des terrasses par classification Random Forest :

1. Découpage des images et création des tuiles
2. Inférence du modèle Random Forest
3. Fusion des rasters de résultats
4. Seuillage des probabilités de prédiction
5. Post-traitements (filtrage, nettoyage)
6. Fusion finale des résultats

**Dépendances R :** `sf`, `terra`, `ranger`

### U-Net (`Unet/`)

Chaîne de traitement par apprentissage profond (segmentation sémantique) :

1. Prétraitement des images satellites et des masques
2. Entraînement du modèle U-Net
3. Découpage en sous-ensembles pour l'inférence
4. Inférence sur les images
5. Fusion des sous-ensembles prédits
6. Génération de la carte de probabilités

**Dépendances Python :** `numpy`, `pandas`, `rasterio`, `scikit-image` (`skimage.exposure`), `Pillow`, `tensorflow`/`keras`

### GEOBIA (`GEOBIA/`)

Approche de classification par objet géographique (Geographic Object-Based Image Analysis).

**Dépendances R :** `terra`

### Analyse paysagère (`eco_paysage/`)

Calcul de métriques d'écologie du paysage sur les résultats de cartographie.

**Dépendances Python :** `processing` 
