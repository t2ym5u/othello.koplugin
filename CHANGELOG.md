# Changelog

All notable changes to this project will be documented in this file.

## [1.3.0] - 2026-10-30

### Added
- "New game" once the game is over (full board, or neither side can move):
  the action bar shows it in place of Pass, so the next game no longer needs
  the menu.

### Changed
- Redesigned play screen, in line with the other games: a full-width action
  bar, a larger board that fills the available room, and one frame around
  it. The status line reads "8×8 · difficulty · Black to move · Black: n ·
  White: n" and wraps in landscape instead of being cut off.
- Title-bar menu in the same order as every other game, with the current
  values shown: New game (was "New"), "Difficulty: Medium", "Players: 1"
  (was "1 player"), and "Play as: Black" (was "I=Black"). Play as is hidden
  in two-player mode, where it meant nothing.
- New README screenshot.

### Fixed
- The thick board border was notched wherever a grid line crossed it, and
  its right and bottom edges spilled just past the board. The border is now
  drawn last, inside the board.

## [1.2.2] - 2026-10-02

### Fixed
- Aligned `1 player (vs AI)` on "1 joueur (contre l'IA)" and the German `AI is
  thinking...` on "KI denkt nach...". `package.loaded` is keyed by module name
  alone, so every `require("i18n")` on the device resolves to one module and
  the first plugin loaded wins it. Every plugin's `i18n_fr.lua` merges into
  that one shared table, where plugins silently overwrite each other's
  translations. This plugin and chess disagreed on both strings, so whichever
  merged last decided them for both.

## [1.2.1] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.2.0] - 2026-09-30

### Added
- Exact endgame solver. With 10 or fewer empty squares left the AI stops
  evaluating and plays the position out to the last disc, so its choice at the
  end is proven rather than guessed. The threshold is 10 deliberately: at 13
  it plays marginally better but one move took 10.8s on a desktop, against
  0.21s worst case at 10.

### Changed
- The AI wins about two games in three against the previous version, and takes
  half the time per move (0.015s against 0.029s at depth 4). Measured over 60
  games with randomised openings: 38-21 with one draw.

### Fixed
- The root search restarted alpha and beta at their extremes for every
  candidate move, which threw away every cutoff between siblings — most of
  what alpha-beta is for. It now carries the best score found so far into each
  subsequent search.
