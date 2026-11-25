# Arena

Arène 3D compétitive pour 3 ou 4 joueurs, faite avec Godot 4 et un serveur dédié autoritaire hébergé sur un NAS Synology.

## Architecture

- Le **serveur** (Godot headless) simule tout : déplacements, physique, dégâts. Il fait foi.
- Les **clients** n'envoient que leurs inputs (UDP via ENet, 60 Hz).
- Le serveur renvoie des **snapshots** de l'état du monde (30 Hz), que les clients interpolent avec environ 100 ms de retard.

Le client et le serveur sont le même projet. Le mode serveur s'active avec `--server`, `--headless` ou un export « dedicated server ».

| Fichier | Rôle |
|---|---|
| `scripts/net/net.gd` | Autoload `Net` : détection du mode serveur, connexion ENet |
| `scripts/main.gd` | Boucle serveur, RPC, spawn des joueurs, menu et caméra côté client |
| `scripts/player.gd` | Simulation (serveur) et interpolation (client) d'un joueur |
| `scenes/arena.tscn` | L'arène (sol, blocs, points de spawn) |

## Tester en local

1. Ouvre le projet dans Godot 4.5 ou plus récent.
2. Va dans *Débogage > Personnaliser les instances lancées…*, active *Plusieurs instances* et mets-en 3.
3. Pour l'instance 1, mets dans les arguments de lancement : `--server --headless`
4. Lance le projet (F5). Dans les deux fenêtres client, clique sur *Rejoindre* avec l'adresse `127.0.0.1`.

Commandes : ZQSD (position WASD), souris, espace pour sauter, Échap pour libérer la souris.

## Déploiement

À chaque push sur `main`, GitHub Actions (`.github/workflows/server-image.yml`) :

1. exporte le serveur dédié avec les presets de `export_presets.cfg` (amd64 et arm64) ;
2. construit l'image Docker multi-architecture ;
3. la publie sur `ghcr.io/alex-deprez/arena-server` (tags `latest` et le SHA du commit).

La variable `GODOT_VERSION` du workflow doit correspondre à la version de l'éditeur.

L'installation sur le NAS (compose, ports, DDNS, mises à jour) est décrite dans le dépôt [ArenaInfra](https://github.com/Alex-Deprez/ArenaInfra).

## Feuille de route

- [x] Serveur autoritaire, inputs, snapshots, interpolation
- [ ] Prédiction côté client et réconciliation (pour supprimer le délai de ton propre perso)
- [ ] Combat : tir, hitscan avec compensation de lag, points de vie, mort et respawn
- [ ] Manches, score, choix de pouvoirs pour les perdants
- [ ] Arène destructible
- [ ] Lobby (salons, choix de l'arène)
