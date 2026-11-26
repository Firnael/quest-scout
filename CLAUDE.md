# Quest Scout

Addon WoW Forever perso : débuts de quête sur la carte (repères colorés + pastilles), et panneau
« Quelle zone maintenant ? ». Remplace Forever Quest Pins (FQP) et Questie. Voir [README.md](README.md).

## Principes (décidés avec l'utilisateur)

- **Rien d'automatique** : pas d'auto-accept, d'auto-turn-in, de Maj pour sauter les dialogues, de
  masquage du suivi en combat. L'utilisateur dit que ça tue l'immersion. Ne pas les proposer.
- **Pas de guidage** : on montre, le joueur décide. Pas de route de leveling.
- **Données** : QuestieDB à l'exécution, plus `Extras.lua`. Saisonnière, effort de guerre et
  donjon se déduisent de `zoneOrSort` (catégories de fête, `-365`, zone de donjon : `Data.lua`).
  `Extras.lua` (écrit à la main, à garder court) liste les quêtes que QuestieDB range ailleurs.
- **Licence MIT** (2026-11-26) : aucun code ni fichier de données repris d'un addon GPL. Ne rien
  copier de FQP, Questie ou QuestieDB (s'en inspirer, réécrire). Ce qui a été retiré pour ça :
  l'ancien `Tags.lua` généré depuis FQP, et des morceaux d'`Options.lua` et de `Pins.lua`.
- **Steam Deck** : l'utilisateur jouera en **mode manette natif** de WoW. Toute modification des
  repères ou de la carte doit penser à la manette autant qu'à la souris (voir Todo).

## Noms

- Nom affiché « Quest Scout », nom technique `QuestScout` (dossier, TOC, `QuestScoutDB`).
  Ancien nom : QuestRange (dépôt renommé `quest-range` → `quest-scout` le 2026-11-12).
- Commande : `/qscout`. Préfixe chat : `ns.Print` (« Quest Scout » en bleu).
- Dépôt : https://github.com/Firnael/quest-scout (public depuis le 2026-11-26, licence MIT), remote SSH.

## Structure

Ordre de chargement (`QuestScout/QuestScout.toc`, Interface 16001, dépend de QuestieDB) :

| Fichier | Rôle |
|---|---|
| `Extras.lua` | `ns.Extras.seasonal`, `instance`, `warEffort` : quêtes que `zoneOrSort` ne range pas dans la bonne catégorie. Écrit à la main |
| `Quests.lua` | `DEFAULTS` et `ns.InitSettings`, quêtes masquées par personnage, rang de métier, `ns.Visibility(q, level)` → `"open"`/`"locked"`/nil + raison FR, `ns.QuestTitle`, `ns.DifficultyColor` |
| `Data.lua` | Index construit une fois par session dans une coroutine : `ns.questById`, `ns.quests` (liste du panneau), `ns.pinsByMap[uiMap]`, `ns.pinsByQuest[id]`, `ns.dungeons`. Regroupe les apparitions d'un donneur (`CLUSTER_RADIUS`) et empile les donneurs proches (`STACK_RADIUS`). `ns.ready`, `ns.onReady` |
| `Advisor.lua` | `ns.RankZones(level)` : classe les zones (XP ajustée façon Classic, densité de hubs, bonus donjon) ; `ns.Verdict` |
| `Panel.lua` | Fenêtre « Quelle zone maintenant ? » (`ns.TogglePanel`, `ns.RefreshPanel`, `ns.ResetPanelPosition`) et son bouton sur la carte du monde |
| `Badges.lua` | `ns.PinBadge(entries)` (priorité classe > métier > donjon), `ns.SetBadge` : icône nue, sans contour ; masque rond seulement pour les icônes carrées (fichiers), pas pour les atlas |
| `Waypoints.lua` | `ns.SetWaypoint` (TomTom ou point Blizzard + SuperTrack), `ns.ClearWaypoint`, `ns.PinTarget`, CVar du marqueur en jeu |
| `Pins.xml` / `Pins.lua` | Repères en **cadres simples** sur le canevas de la carte, pas en `MapCanvasPinMixin` (en mode manette, Blizzard parcourt ses repères et un repère d'addon « taint » la carte). Le data provider sert seulement aux événements (affichage, changement de carte, zoom). Placement et échelle refaits à la main (`Place`), survol manette par sondage du curseur et infobulle à part (`QuestScoutTooltip`), clic manette différé d'une image. Atlas `QuestNormal` désaturé puis teinté, points d'emplacements au survol, projection sur continent/monde (`C_Map.GetMapRectOnMap`), clic / Maj-clic, `ns.RefreshPins` |
| `Options.lua` | Panneau Options > AddOns (canvas, deux colonnes) et la commande `/qscout` |

Outils (`tools/`, LuaJIT) :
- `offline-rank.lua` : lance Data + Advisor hors jeu avec l'émulateur d'un clone de QuestieDB.
  Exécuter le code de QuestieDB a été refusé par le mode auto : demander à l'utilisateur avant.

## API QuestieDB (LibQuestieDB, contrat 4)

- `QuestDB.GetAll(id, keys)`, `QuestDB.GetAllIds`, `NpcDB.spawns/name`, `ObjectDB`,
  `Support.Get("ZoneDB")`, `Support.Get("QuestXP")`.
- Les getters numériques renvoient **0, jamais nil**. `requiredSkill` = `{skillLineId, valeur}`.

## Conventions

- **Lua 5.1**. Code et commentaires en anglais ; les commentaires expliquent le *pourquoi*.
- **Texte visible en français directement** (pas de table de locales), en tutoyant. Pas de
  morceaux de phrase concaténés quand on peut l'éviter.
- Interface aux modèles du jeu : `UICheckButtonTemplate`, `OptionsSliderTemplate`,
  `UIPanelButtonTemplate`, atlas du client.
- **Combat** : le MapCanvas de Forever appelait une méthode protégée quand on ajoutait ou retirait
  ses repères. `RefreshAllData` est différé hors combat (`PLAYER_REGEN_ENABLED`). Avec les cadres
  simples, ce n'est sans doute plus nécessaire ; le garder tant que ce n'est pas vérifié en jeu.
- Commits : `<gitmoji> <scope> - <sujet>`, une seule ligne, sans `Co-Authored-By`.

## Vérifier le code

```sh
for f in QuestScout/*.lua tools/*.lua; do luajit -bl "$f" >/dev/null || echo "SYNTAX $f"; done
xmllint --noout QuestScout/Pins.xml
```

Pas de luacheck sur ce Mac. Le comportement se teste en jeu : le dossier AddOns contient un lien
vers `QuestScout/` de ce dépôt, donc un `/reload` suffit (relancer le jeu pour un nouveau fichier
dans le TOC). Erreurs avec BugSack/BugGrabber (installés) ; `/qscout debug` et `/qscout why <id>`.

## Todo

- [ ] **Premier test en jeu** : repères sur une zone et un continent, couleurs, pastilles sans
  contour (lisibilité d'une icône de métier sombre), points au survol, Maj-clic puis
  `/qscout unhide all`, panneau d'options, `why` et `track`, TomTom et marqueur en jeu.
  Depuis le passage aux cadres simples (2026-11-17), vérifier aussi : repères au bon endroit en
  zoomant / dézoomant et en agrandissant la carte, au-dessus de la carte et du brouillard, taille
  stable, clic droit sur un repère qui dézoome toujours.
- [ ] **Bouton « Quelle zone ? »** (haut droite de la carte) : pas de chevauchement avec les
  boutons de la carte ou d'OpenMap, devant les repères ; le panneau (strate `DIALOG`) passe
  au-dessus de la carte. Option pour le masquer : pas faite, à voir.
- [ ] **Support manette (Steam Deck)** : même approche que FQP (`TylerAkins/forever-quest-pins`,
  `MapPins.lua`), réécrite, pas encore testé. Sur le Deck : survol d'un repère au stick (infobulle et points),
  clic A (point de passage), puis fermer la carte sans popup « action bloquée ». Masquer un
  repère (Maj-clic) n'a pas encore d'équivalent manette. Inconnu : le A du curseur manette
  atteint-il nos boutons, ou la carte le garde-t-elle ? FQP compte dessus, le code de Blizzard ne
  le prouve pas. Code de la carte Forever : `Ketho/wow-ui-source-forever`, `Blizzard_MapCanvas`
  (`UpdateGamepadCursor`, `ClickHoveredPins`).
- [ ] **Publication (CurseForge)** : envisagée le 2026-11-17. Public : les joueurs qui quittent
  Questie pour plus léger ; « rien d'automatique » est la vraie différence avec FQP (qui a de
  l'auto-accept et des icônes sur les PNJ). Avant : tests en jeu ci-dessus, fichier `LICENSE` MIT
  fait, traduction anglaise (texte français
  en dur, contraire à la convention actuelle : à décider), prévenir l'auteur de FQP.
