# Terrasses Ventoux

Ce dépôt regroupe les scripts de cartographie et de détection des terrasses agricoles sur le Mont Ventoux, développés dans le cadre du Master 2 GEOTER (2025-2026).

## Données

Les données associées à ce projet sont archivées et accessibles via Zenodo :

[https://doi.org/10.5281/zenodo.19098311](https://doi.org/10.5281/zenodo.19098311)

## Structure du dépôt

```text
.
├── methode_approuvee/       # Méthodes validées et conservées
│   ├── randomforest/        # Chaîne de traitement Random Forest
│   │   ├── entrainement/
│   │   │   ├── 01_IMAGE_ENTRAINEMENT.R
│   │   │   ├── 02_RANDOM_FOREST.R
│   │   │   └── 03_INFERENCE_RANDOM_FOREST.R
│   │   └── inference/
│   │       ├── 01_DECOUPE_IMAGES_DOSSIERS.R
│   │       ├── 02_INFERENCE_RANDOM_FOREST.R
│   │       ├── 03_FUSIONNER_RASTER.R
│   │       ├── 04_SEUILS.R
│   │       ├── 05_POST_TRAITEMENTS.R
│   │       └── 06_FUSION.R
│   └── rupture_pente/       # Détection et tri des ruptures de pente (MSRM)
│       └── rupture_pente_script.R
│
├── methode_abandonnee/      # Méthodes explorées mais non retenues
│   ├── GEOBIA/              # Approche orientée objet (GEOBIA)
│   │   └── Geobia.R
│   ├── Unet/                # Chaîne de traitement U-Net (apprentissage profond)
│   │   ├── modele/
│   │   │   └── best_model.keras
│   │   └── scripts/
│   │       ├── 01_PREPROCESSER.py
│   │       ├── 02_ENTRAINER.ipynb
│   │       ├── 03_DECOUPER_SOUS_ENSEMBLE.py
│   │       ├── 04_INFERER.py
│   │       ├── 05_FUSIONNER_SOUS_ENSEMBLE.py
│   │       └── 06_CARTE_PROBA.py
│   └── eco_paysage/         # Analyse de métriques paysagères
│       ├── 01_Workflow_general.py
│       ├── 02_Test_buffer.py
│       └── 03_Test_pentes.py
│
└── lien_donnees_zenodo.txt  # Référence aux données sur Zenodo
```

## Méthodes Approuvées

### Random Forest (`methode_approuvee/randomforest/`)

Chaîne de traitement complète en R pour la détection des terrasses par classification Random Forest. Séparée en deux phases : entraînement et inférence.

**Dépendances R :** `sf`, `terra`, `ranger`, `future`, `future.callr`

### Rupture de pente (`methode_approuvee/rupture_pente/`)

Pipeline de détection et tri des ruptures de pente (MSRM) avec extraction morphologique et filtrage spatial.

**Dépendances R :** `terra`, `tictoc`

## Méthodes Abandonnées

### U-Net (`methode_abandonnee/Unet/`)

Chaîne de traitement par apprentissage profond (segmentation sémantique) :

1. Prétraitement des images satellites et des masques
2. Entraînement du modèle U-Net
3. Découpage en sous-ensembles pour l'inférence
4. Inférence sur les images
5. Fusion des sous-ensembles prédits
6. Génération de la carte de probabilités

**Dépendances Python :** `numpy`, `pandas`, `rasterio`, `scikit-image` (`skimage.exposure`), `Pillow`, `tensorflow`/`keras`

### GEOBIA (`methode_abandonnee/GEOBIA/`)

Approche de classification par objet géographique (Geographic Object-Based Image Analysis).

**Dépendances R :** `terra`

### Analyse paysagère (`methode_abandonnee/eco_paysage/`)

Calcul de métriques d'écologie du paysage sur les résultats de cartographie.

**Dépendances Python :** `os`, `processing`, `qgis.core`
