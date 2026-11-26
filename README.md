# Quest Scout

Addon WoW Forever : les débuts de quête sur la carte du monde, et un panneau « Quelle zone
maintenant ? » qui classe les zones selon les quêtes qui restent à ton niveau. Rien d'automatique :
pas d'acceptation ni de rendu de quête, pas de route de leveling. Tu choisis où aller.

## Fonctionnalités

- **Repères sur la carte** : un « ! » par donneur de quête, coloré selon la difficulté (comme le
  jeu). Les quêtes à venir (jusqu'à 3 niveaux au-dessus) sont en gris argenté.
- **Pastilles** sur le repère : classe, métier ou donjon.
- **Plusieurs emplacements** : quand un donneur apparaît à plusieurs endroits, le survol du repère
  affiche un petit point jaune sur chaque emplacement possible.
- **Infobulle en français** : donneur, quêtes, niveaux, type de quête, raison si elle est grisée.
- **Clic** : point de passage (point de la carte Blizzard, ou TomTom s'il est installé, marqueur
  en jeu en option). **Maj-clic** : masque les quêtes du repère pour ce personnage.
- **Cartes de continent et du monde** : les repères des zones y sont projetés (optionnel). Marche
  avec OpenMap.
- **Filtres** : par type (normale, classe, métier, donjon, répétable, saisonnière, effort de guerre
  d'AQ) et par niveau (bas niveau, plage autour du tien), taille des repères de 50 à 150 %.
- **Panneau « Quelle zone maintenant ? »** : les zones classées par XP restante pour ta plage de
  niveaux, avec le nombre de quêtes et de hubs. S'ouvre avec le bouton « Quelle zone ? » en haut
  à droite de la carte du monde, ou avec `/qscout`.

## Prérequis

- **[QuestieDB](https://github.com/Questie/QuestieDB)** (obligatoire) : la base de quêtes, de PNJ
  et d'objets. Prendre le zip « Forever ».
- TomTom (optionnel) : utilisé pour les points de passage s'il est installé.
- Questie n'est pas nécessaire. Quest Scout remplace Forever Quest Pins : ne pas activer les deux.

## Installation

1. Copier le dossier `QuestScout` dans `<dossier du jeu>/_forever_/Interface/AddOns/`.
2. Installer QuestieDB au même endroit.
3. Relancer le jeu.

Pour développer depuis le dépôt sans copie, un lien suffit (macOS) :

```sh
ln -sfn ~/git/perso/wow-addons/quest-scout/QuestScout "/Applications/World of Warcraft/_forever_/Interface/AddOns/QuestScout"
```

## Commandes

| Commande | Effet |
|---|---|
| `/qscout` | Ouvre ou ferme le panneau « Quelle zone maintenant ? » |
| `/qscout <en dessous> <au-dessus>` | Plage de niveaux du panneau (ex. `/qscout 2 4`) |
| `/qscout options` | Réglages (aussi dans Options > AddOns > Quest Scout) |
| `/qscout on` / `off` | Affiche ou masque les repères |
| `/qscout badges` | Active ou coupe les pastilles |
| `/qscout track <id>` / `clear` | Point de passage vers une quête / l'enlever |
| `/qscout unhide <id \| all>` / `hidden` | Réaffiche des quêtes masquées / les compte |
| `/qscout why <id>` | Explique pourquoi une quête est affichée, grisée ou masquée |
| `/qscout debug` / `refresh` / `reset` | IDs dans les infobulles / redessine / replace le panneau |

## Origine des données

Tout vient de QuestieDB, lu au chargement : les nouvelles quêtes de QuestieDB apparaissent sans
mise à jour de Quest Scout. Les étiquettes saisonnière, donjon et effort de guerre d'AQ viennent
de la catégorie de chaque quête dans QuestieDB (fête, effort de guerre, zone de donjon).
`QuestScout/Extras.lua` complète les quêtes que QuestieDB range ailleurs : des quêtes de fête
sous « Spécial », celles de l'effort de guerre à Silithus, et les quêtes de donjon données hors
du donjon.

Merci à [Forever Quest Pins](https://www.curseforge.com/wow/addons/forever-quest-pins), qui a
montré comment faire marcher des repères avec la manette.

## Licence

MIT, voir [LICENSE](LICENSE).

Projet perso. Les conventions et la structure du code sont dans [CLAUDE.md](CLAUDE.md).
