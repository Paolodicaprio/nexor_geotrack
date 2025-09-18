## Prérequis

Avant de commencer, assurez-vous d'avoir les outils suivants installés sur votre machine :

- Python 3.10 ou supérieur
- `pip` (gestionnaire de paquets Python)
- `virtualenv` (optionnel mais recommandé)
- Git

---

## Installation

### 1. Cloner le dépôt

Clonez le dépôt sur votre machine et basculer sur la branche `main` :

```bash
git clone https://github.com/Paolodicaprio/nexor_geotrack.git
cd nexor_geotrack
```

### 2. Créer et activer un environnement virtuel

Créez un environnement virtuel pour isoler les dépendances du projet :

```bash
python -m venv venv
source venv/bin/activate
```

### 3. Installer les dépendances
Installez les dépendances nécessaires à partir du fichier requirements.txt :

```bash
pip install -r requirements.txt
```

### 4. Configurer les variables d'environnement
Créez un fichier .env à la racine du projet et configurez les variables comme dans .env.example :


## Lancement du serveur

Demarrer le serveur avec la commande :

```bash
uvicorn app.main:app --reload
```

## Administration
Accédez à la documentation de l'api: [http://127.0.0.1:8000/docs.] 
## Important

- Tous les utilisateurs fictifs présents dans la base de données ont pour mot de passe : `azerty123`.
- Afin de lancer les jobs d'arriere plan, executez le script `start_tasks.sh` situé a la racine du projet si vous etes sous linux ou celui ci `start_tasks.bat` si vous etes sur windows. Il se pourrait que vous accordiez le droit d'execution au script avant de pouvoir l'utiliser (linux).