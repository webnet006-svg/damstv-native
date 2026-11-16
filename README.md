# DAMS TV Native 📺

Application Flutter native Android dédiée à la lecture fluide et universelle de flux IPTV (M3U/M3U8), contournant les restrictions de streaming réseau (HTTP, CORS et erreurs 403 Forbidden).

---

## 🚀 Fonctionnalités principales

- **Parseur M3U & M3U8 intelligent** :
  - Extraction automatique du nom des chaînes, logos (`tvg-logo`) et catégories/groupes (`group-title`).
  - Filtrage des URLs valides (HTTP, HTTPS, RTSP, RTMP, MMS).
  - Téléchargement sécurisé et rapide de la playlist via le package `http`.
- **Contournement des restrictions HTTP / CORS / 403** :
  - Injection des en-têtes réseau `User-Agent` (`Mozilla/5.0...`) et `Referer` (`https://www.google.com/`) dans les requêtes de chargement de playlist et dans les flux vidéo libVLC.
  - Autorisation du trafic clair HTTP non sécurisé via `android:usesCleartextTraffic="true"`.
- **Lecteur Vidéo Haute Performance (VLC)** :
  - Moteur `flutter_vlc_player` avec accélération matérielle complète (`HwAcc.full`).
  - Commandes de lecture complètes (Lecture / Pause, Avance / Retour 10s, Rechargement / Reconnexion de flux).
  - Buffer optimisé pour la stabilité du direct (`network-caching` et `live-caching`).
- **Interface Utilisateur Moderne** :
  - Thème sombre épuré Material 3 adapté aux grands et petits écrans.
  - Barre de recherche en temps réel par chaîne ou catégorie.
  - Compteur de chaînes et gestion visuelle des statuts de lecture.

---

## 🛠️ Architecture Technique

| Composant | Spécification |
| :--- | :--- |
| **Framework** | Flutter 3.16.0 (Dart SDK `>=3.0.0 <4.0.0`) |
| **Moteur Vidéo** | `flutter_vlc_player: ^7.4.1` (libVLC natif) |
| **Réseau** | `http: ^1.1.0` |
| **Permissions** | `permission_handler: ^11.0.1` |
| **Plateforme cible** | Android (API min 21+ / Android 5.0 Lollipop et supérieur) |
| **CI / CD** | GitHub Actions (`ubuntu-latest`, Java 12 Zulu, compilation automatique de l'APK) |

---

## 📦 Compilation automatique & Téléchargement de l'APK

Un workflow GitHub Actions automatisé (`.github/workflows/build.yml`) compile l'APK à chaque push sur le dépôt :

1. Rendez-vous sur l'onglet **Actions** de votre dépôt GitHub.
2. Cliquez sur le dernier workflow exécuté nommé **Build APK**.
3. Dans la section **Artifacts** en bas de page, téléchargez l'archive **`DAMS-TV-APK`**.
4. Installez le fichier `app-release.apk` sur votre appareil Android ou votre box TV.

---

## 📱 Utilisation

1. Lancez l'application **DAMS TV Native** sur votre appareil Android.
2. Collez l'URL de votre playlist M3U dans le champ prévu à cet effet.
3. Cliquez sur **Télécharger la playlist**.
4. Parcourez la liste ou utilisez la barre de recherche pour trouver vos chaînes.
5. Cliquez sur n'importe quelle chaîne pour lancer immédiatement le lecteur VLC en plein écran ou au format 16:9.
