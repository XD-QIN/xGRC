# xGRC — Textes App Store en français / French App Store Copy

Textes prêts à coller dans App Store Connect. Chaque champ indique sa limite de
caractères ; le nombre entre crochets sous chaque bloc est le décompte réel du
texte proposé, mesuré avec `len()` en Python, espaces insécables comprises.

**Localisation App Store Connect : « French » (locale de l’app `fr`).** L’app
ne livre aucune chaîne `fr-CA` : un appareil réglé en français canadien affiche
l’interface `fr`. Si la localisation « French (Canada) » est activée, elle
reprend ce texte tel quel. L’original anglais est
[appstore_intro.md](appstore_intro.md) ; ce fichier lui correspond section par
section.

**Brouillon rédigé par machine.** Ce texte, comme les chaînes françaises de
l’app (`fr.json`), doit être relu par un francophone natif avant toute
soumission — ton, coquilles, espaces insécables — puis remesuré.

**Un changement qui touche une affirmation doit être reporté dans tous les
fichiers de langue** (les dix `appstore_intro_*.md` et l’anglais). Aucune
affirmation n’est ajoutée ici : fonctions, limites, appareils pris en charge et
leurs réserves, confidentialité, tout suit l’anglais.

**Les notes pour App Review, les réponses App Privacy et les textes TestFlight
restent en anglais** : voir [appstore_intro.md](appstore_intro.md).

**Typographie.** Espace insécable (U+00A0) avant `:` `;` `?` `!` et à
l’intérieur des guillemets « », comme dans l’app ; chacune compte pour un
caractère. Vouvoiement partout, comme l’app.

---

## Terminologie — tirée de `fr.json`

La fiche emploie les mots que l’utilisateur lit à l’écran. Si l’app change une
chaîne, cette table et ce texte changent avec elle.

| English | fr (app) |
|---|---|
| Shutter (bouton, section) | Déclencheur |
| shutter (mécanisme) | obturateur |
| Shoot | Déclencher |
| Fired, confirmed | Déclenché, confirmé |
| Sent, not confirmed | Envoyé, non confirmé |
| confirmed / sent (compteurs) | confirmés / envoyés |
| Focus | Mise au point |
| AF hold | Maintien AF |
| half-press | mi-course |
| Bulb | Pose B (réglage de l’appareil : `BULB`, tel quel) |
| Release delay | Délai de déclenchement |
| Intervalometer | Intervallomètre |
| Timelapse | Timelapse |
| Frames | Vues |
| Shutter open (temps d’ouverture) | Temps de pose |
| Geotag / Geotagging | Géomarquage |
| Remote + Geotag / Remote only / Geotag only | Télécommande + géomarquage / Télécommande seule / Géomarquage seul |
| GPS tracks / Track | Traces GPS / Trace |
| location | position (l’autorisation iOS : « Localisation ») |
| fix (GPS) | position |
| push / pushes | envoi / envois |
| Session / End session | Session / Terminer la session |
| Pair / Pairing mode / Pair again | Jumeler / Mode jumelage / Jumeler à nouveau |
| Forget | Oublier |
| Auto reconnect / Auto disconnect | Reconnexion auto / Déconnexion auto |
| Tap to shoot (Apple Watch) | Toucher pour déclencher |
| Double Tap (geste Apple Watch) | Toucher deux fois |
| Live Activity / Dynamic Island / Lock Screen | Activité en direct / Dynamic Island / écran verrouillé |
| Smart Stack | Pile intelligente |
| Settings | Réglages |
| camera | appareil photo (dans les phrases : « l’appareil ») |

Notes :

- **« Déclenché » ne se dit que d’une prise confirmée par l’appareil**,
  « Envoyé » d’une commande partie sans confirmation. C’est toute la promesse
  de l’app ; la fiche ne mélange jamais les deux.
- **« Pose B »**, le terme des fabricants en français ; l’app garde `BULB` en
  capitales quand elle parle du réglage de l’appareil.
- **Les noms de menus des appareils restent en anglais dans l’app** (Bluetooth
  Rmt Ctrl, Location Info. Link, Pairing Registration…) faute de libellé
  officiel français vérifié. La fiche ne les cite pas.

---

## Aperçu / At a glance

| Champ | fr |
|---|---|
| Catégorie principale | Photo & Video |
| Catégorie secondaire | Utilities |
| Classification | 4+ |
| Compatibilité | iOS 17.0 ou version ultérieure (iPhone, iPad) ; watchOS 10.0 ou version ultérieure (Apple Watch) |
| Langues de l’app | 13 |

Les catégories se choisissent dans App Store Connect, qui les traduit lui-même.

---

## Nom de l’app (30 caractères)

```
xGRC - Télécommande photo GPS
```
[29]

Le nom sous l’icône reste `xGRC`. « Télécommande », « photo » et « GPS » sont
indexés par le nom et ne sont pas rachetés dans les mots-clés. L’anglais dit
*Camera Remote & Geotag* ; « géomarquage » ne tient pas dans 30 caractères, le
sous-titre et les mots-clés le portent.

Alternative :

```
xGRC - Télécommande et GPS
```
[26]

---

## Sous-titre (30 caractères)

```
Déclencheur et GPS au poignet
```
[29]

Calqué sur *Shutter and GPS on your wrist*. « Déclencheur » et « poignet » sont
indexés ici et absents des mots-clés.

---

## Texte promotionnel (170 caractères — modifiable sans nouveau build)

```
Déclenchez depuis iPhone, iPad ou Apple Watch : pose B minutée, délai de déclenchement, timelapses, GPS dans chaque photo. Sans dongle ni compte. Rien n’est collecté.
```
[166]

Réécrit plutôt que traduit mot à mot (la traduction directe dépassait 170).
Toutes les affirmations de l’anglais restent : pose B minutée, délai de
déclenchement, timelapses, GPS dans chaque photo ; sans dongle, sans compte,
rien n’est collecté.

---

## Mots-clés (100 caractères, séparés par des virgules, sans espaces)

```
intervallomètre,timelapse,pose,bulb,hybride,exif,géomarquage,géolocalisation,reflex,retardateur
```
[95]

Aucun mot du nom ou du sous-titre (`xGRC`, `télécommande`, `photo`, `GPS`,
`déclencheur`, `poignet`). **Aucune marque** (Sony, Fujifilm, Canon, Nikon,
Ricoh, ni Bluetooth) : motif de refus courant. `retardateur` est le mot que
cherche un photographe français pour un déclenchement différé ; l’app dit
« Délai de déclenchement ».

---

## Description (4 000 caractères)

Coller le bloc entier. Les paragraphes sont volontairement écrits sur une seule
ligne : App Store Connect conserve chaque retour à la ligne.

```
xGRC fait de votre iPhone, iPad et Apple Watch une télécommande Bluetooth pour votre appareil photo, et son GPS. L’app parle directement au Bluetooth intégré des appareils Sony, Fujifilm, Canon, Nikon et Ricoh : sans dongle, sans Wi-Fi, sans attendre l’app du fabricant.

UN TOUCHER POUR LA MISE AU POINT, DEUX POUR DÉCLENCHER
Le déclencheur fonctionne partout de la même façon. Touchez une fois pour faire la mise au point, deux fois pour déclencher. Activez Maintien AF pour garder la mise au point verrouillée en attendant le bon moment.

« DÉCLENCHÉ » SEULEMENT S’IL A DÉCLENCHÉ
Quand l’appareil confirme une prise, xGRC affiche Déclenché et la compte. Quand le Bluetooth de l’appareil ne prévoit pas de confirmation, xGRC affiche Envoyé à la place. Les compteurs confirmés et envoyés ne font jamais semblant.

LES POSES LONGUES SANS LE CÂBLE
• Pose B minutée : réglez une durée jusqu’à 99 min 59 s, touchez une fois, et l’obturateur se ferme tout seul à la fin du compte à rebours
• Délai de déclenchement de 1 à 60 secondes, pour que votre main ait quitté l’appareil quand il déclenche
• Intervallomètre pour les timelapses : intervalle, nombre de vues ou jusqu’à l’arrêt, délai de démarrage et temps de pose facultatif

LE GPS DANS CHAQUE PHOTO
xGRC envoie votre position et l’heure à l’appareil photo, qui les inscrit dans chaque photo qu’il prend. Sur iPhone, le géomarquage continue avec le téléphone verrouillé et s’affiche dans la Dynamic Island et sur l’écran verrouillé. Sur Apple Watch, il fonctionne seul, téléphone resté à la maison. Chaque session conserve sa trace GPS sur votre iPhone, iPad ou Apple Watch, chaque position avec son heure : voyez-la en points sur une carte sur iPhone et iPad, et exportez-la en fichier CSV depuis n’importe lequel des trois.

UNE VRAIE APP APPLE WATCH
Recherchez, jumelez, déclenchez et géomarquez depuis la montre, sans iPhone. Sur Apple Watch Series 9, Ultra 2 et modèles ultérieurs, le geste Toucher deux fois, de l’index et du pouce, déclenche : la main qui tient l’appareil reste où elle est. Activez Toucher pour déclencher, et un toucher sur l’écran fait la mise au point puis déclenche. Une tuile de la Pile intelligente montre la session d’un coup d’œil.

CONÇU POUR LE TERRAIN
• Choisissez Télécommande + géomarquage, Télécommande seule ou Géomarquage seul
• La reconnexion auto reprend la session quand l’appareil se réveille ou revient à portée
• La déconnexion auto libère l’appareil après un moment d’inactivité, 15 minutes sauf si vous changez ce réglage
• Raccourcis et commandes : Déclencher, Mise au point, Lancer et Arrêter le géomarquage
• Apparence claire, sombre ou système sur iPhone et iPad
• Grandes commandes utilisables avec des gants, retours haptiques nets
• Treize langues, au choix dans Réglages

COMPATIBLE AVEC
• Sony Alpha, ZV, RX et FX dotés de la télécommande Bluetooth
• Fujifilm X et GFX
• Canon EOS et PowerShot, en jumelage Télécommande ou Smartphone
• Nikon, en mode télécommande (ML-L7)
• Ricoh GR III, GR IIIx et GR IV
Ce que chaque appareil peut faire en Bluetooth varie : mise au point, pose B et géomarquage ne sont pas disponibles sur toutes les marques ni dans tous les modes. La liste complète est sur la page GitHub du projet, accessible depuis À propos.

PRIVÉ PAR CONCEPTION
Aucun compte, aucune mesure d’audience, aucune publicité, aucun serveur. Votre position ne va qu’à votre appareil photo, en Bluetooth, et dans des traces qui restent sur votre iPhone, iPad ou Apple Watch jusqu’à ce que vous les exportiez ou les supprimiez. xGRC est open source sous licence GPLv3.

xGRC n’est affilié ni à Sony, ni à Fujifilm, ni à Canon, ni à Nikon, ni à Ricoh. Les noms de marque appartiennent à leurs propriétaires.
```
[3 720]

Détails qui ne sont pas des coquilles :

- **« 99 min 59 s », « 1 s » et « 15 minutes » avec espace insécable** entre
  le nombre et l’unité (norme typographique française).
- **« dongle »** est le mot courant en français pour un adaptateur Bluetooth
  à brancher ; « boîtier » se confondrait avec le boîtier de l’appareil.
- **« Raccourcis et commandes »** : *Shortcuts and Controls*, les noms
  qu’Apple emploie en français (app Raccourcis, commandes du Centre de
  contrôle).
- **Absent exprès, comme en anglais** : la transcription Bluetooth intégrée,
  Garder l’appareil éveillé, la barre latérale de l’iPad.

---

## Nouveautés (4 000 caractères) — version 1.0

Les Nouveautés de la première version ne s’affichent pas sur la fiche, mais
App Store Connect les demande.

```
Première version de xGRC : une télécommande Bluetooth et un géomarqueur GPS pour appareil photo, sur iPhone, iPad et Apple Watch.
```
[129]

---

## Légendes des captures d’écran

Deux lignes courtes chacune ; elles vont dans `lines` de
`AppStorePreview/tools/frames.json` (une chaîne par ligne) avant le rendu. Le
décompte entre crochets compte les deux lignes et le retour à la ligne.

1. Écran de session, Sony connecté et géomarquage actif

```
Une télécommande pour votre appareil.
Sans dongle ni app du fabricant.
```
[70]

2. Déclenché · confirmé, 36 prises confirmées

```
« Déclenché » seulement quand
l’appareil le confirme.
```
[53]

3. Pose B de 2 min 30 s en cours

```
Réglez une pose B.
Un toucher, elle se ferme seule.
```
[51]

4. Intervallomètre en cours

```
Des timelapses
sans câble à emporter.
```
[37]

5. Écran Géomarquage avec sa carte

```
Le GPS de votre téléphone,
dans chaque photo.
```
[45]

6. Liste des appareils (pas sur iPad)

```
Pour les hybrides
et les compacts.
```
[34]

7. Délai de 10 s en cours

```
Un délai de déclenchement,
les mains loin de l’appareil.
```
[56]

Les captures doivent être refaites avec l’app en français : des écrans
anglais sous une fiche française se remarquent. Les captures Apple Watch n’ont
pas de légende.

---

## Notes pour App Review, App Privacy, TestFlight

**Ils restent en anglais. Ne pas traduire.** Coller tels quels les blocs de
[appstore_intro.md](appstore_intro.md).
