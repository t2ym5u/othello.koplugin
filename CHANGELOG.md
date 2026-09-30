# Changelog

All notable changes to this project will be documented in this file.

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
