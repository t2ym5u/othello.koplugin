-- ---------------------------------------------------------------------------
-- OthelloBoard — game logic for Othello/Reversi (8x8)
--
-- grid[r][c]:
--   0 = empty
--   1 = black disc
--   2 = white disc
--
-- r=1 is the top row, c=1 is the leftmost column.
-- Black goes first.
-- Initial position:
--   (4,4)=white  (4,5)=black
--   (5,4)=black  (5,5)=white
-- ---------------------------------------------------------------------------

local OthelloBoard = {}
OthelloBoard.__index = OthelloBoard

local BLACK = 1
local WHITE = 2
local INF   = 1e9

-- All 8 directions
local DIRS = {
    {-1, -1}, {-1, 0}, {-1, 1},
    { 0, -1},           { 0, 1},
    { 1, -1}, { 1, 0}, { 1, 1},
}

-- Corner positions (1-indexed)
local CORNERS = { {1,1}, {1,8}, {8,1}, {8,8} }
local CORNER_SET = {}
for _, pos in ipairs(CORNERS) do
    CORNER_SET[pos[1] * 10 + pos[2]] = true
end

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

function OthelloBoard:new()
    local o = setmetatable({}, self)
    o.grid     = {}
    o.turn     = "black"
    o.status   = "playing"
    o.winner   = nil
    o.last_r   = nil
    o.last_c   = nil
    for r = 1, 8 do
        o.grid[r] = {}
        for c = 1, 8 do
            o.grid[r][c] = 0
        end
    end
    return o
end

-- ---------------------------------------------------------------------------
-- Reset / initial position
-- ---------------------------------------------------------------------------

function OthelloBoard:reset()
    for r = 1, 8 do
        for c = 1, 8 do
            self.grid[r][c] = 0
        end
    end
    -- Standard Othello starting position
    self.grid[4][4] = WHITE
    self.grid[4][5] = BLACK
    self.grid[5][4] = BLACK
    self.grid[5][5] = WHITE

    self.turn   = "black"
    self.status = "playing"
    self.winner = nil
    self.last_r = nil
    self.last_c = nil
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function inBounds(r, c)
    return r >= 1 and r <= 8 and c >= 1 and c <= 8
end

local function colorVal(color)
    return (color == "black") and BLACK or WHITE
end

local function oppColor(color)
    return (color == "black") and "white" or "black"
end

local function oppVal(v)
    return (v == BLACK) and WHITE or BLACK
end

-- ---------------------------------------------------------------------------
-- getFlips — list of {r,c} discs that would be flipped by placing at (r,c)
-- ---------------------------------------------------------------------------

function OthelloBoard:getFlips(r, c, color)
    local grid = self.grid
    if grid[r][c] ~= 0 then return {} end
    local my_val  = colorVal(color)
    local opp_val = oppVal(my_val)
    local flips   = {}

    for _, d in ipairs(DIRS) do
        local dr, dc   = d[1], d[2]
        local nr, nc   = r + dr, c + dc
        local line     = {}
        while inBounds(nr, nc) and grid[nr][nc] == opp_val do
            line[#line + 1] = { nr, nc }
            nr = nr + dr
            nc = nc + dc
        end
        if #line > 0 and inBounds(nr, nc) and grid[nr][nc] == my_val then
            for _, pos in ipairs(line) do
                flips[#flips + 1] = { r = pos[1], c = pos[2] }
            end
        end
    end
    return flips
end

-- ---------------------------------------------------------------------------
-- isValidMove
-- ---------------------------------------------------------------------------

function OthelloBoard:isValidMove(r, c, color)
    if self.grid[r][c] ~= 0 then return false end
    return #self:getFlips(r, c, color) > 0
end

-- ---------------------------------------------------------------------------
-- getValidMoves — list of {r,c}
-- ---------------------------------------------------------------------------

function OthelloBoard:getValidMoves(color)
    local moves = {}
    for r = 1, 8 do
        for c = 1, 8 do
            if self:isValidMove(r, c, color) then
                moves[#moves + 1] = { r = r, c = c }
            end
        end
    end
    return moves
end

-- ---------------------------------------------------------------------------
-- placeDisk — place a disc for self.turn at (r,c)
-- Returns: "ok", "invalid", "skip", "ended"
-- ---------------------------------------------------------------------------

function OthelloBoard:placeDisk(r, c)
    if self.status ~= "playing" then return "invalid" end
    local color = self.turn
    local flips = self:getFlips(r, c, color)
    if #flips == 0 then return "invalid" end

    -- Place disc and flip
    local my_val = colorVal(color)
    self.grid[r][c] = my_val
    for _, pos in ipairs(flips) do
        self.grid[pos.r][pos.c] = my_val
    end
    self.last_r = r
    self.last_c = c

    -- Switch turn
    return self:_advanceTurn()
end

-- Internal: determine whose turn comes next, handle skips and game end.
-- Returns "ok", "skip", or "ended".
function OthelloBoard:_advanceTurn()
    local next_color = oppColor(self.turn)
    local next_moves = self:getValidMoves(next_color)

    if #next_moves > 0 then
        self.turn = next_color
        return "ok"
    end

    -- Next player has no move — check if current player can continue
    local curr_moves = self:getValidMoves(self.turn)
    if #curr_moves > 0 then
        -- Skip: current player keeps their turn
        -- (turn stays the same)
        return "skip"
    end

    -- Neither player can move — game over
    self.status = "ended"
    local bc, wc = self:countDiscs()
    if bc > wc then
        self.winner = "black"
    elseif wc > bc then
        self.winner = "white"
    else
        self.winner = "draw"
    end
    return "ended"
end

-- ---------------------------------------------------------------------------
-- countDiscs
-- ---------------------------------------------------------------------------

function OthelloBoard:countDiscs()
    local black, white = 0, 0
    for r = 1, 8 do
        for c = 1, 8 do
            local v = self.grid[r][c]
            if v == BLACK then black = black + 1
            elseif v == WHITE then white = white + 1 end
        end
    end
    return black, white
end

-- ---------------------------------------------------------------------------
-- Serialize / Load
-- ---------------------------------------------------------------------------

function OthelloBoard:serialize()
    local grid_copy = {}
    for r = 1, 8 do
        grid_copy[r] = {}
        for c = 1, 8 do
            grid_copy[r][c] = self.grid[r][c]
        end
    end
    return {
        grid   = grid_copy,
        turn   = self.turn,
        status = self.status,
        winner = self.winner,
        last_r = self.last_r,
        last_c = self.last_c,
    }
end

function OthelloBoard:load(data)
    if type(data) ~= "table" or type(data.grid) ~= "table" then
        return false
    end
    for r = 1, 8 do
        if type(data.grid[r]) ~= "table" then return false end
        for c = 1, 8 do
            local v = data.grid[r][c]
            if type(v) ~= "number" or v < 0 or v > 2 then return false end
            self.grid[r][c] = v
        end
    end
    self.turn   = (data.turn == "white") and "white" or "black"
    self.status = (data.status == "ended") and "ended" or "playing"
    self.winner = data.winner
    self.last_r = data.last_r
    self.last_c = data.last_c
    return true
end

-- ---------------------------------------------------------------------------
-- AI — iterative-deepening alpha-beta (negamax) under a time budget
--
-- The search runs on a flat 10x10 array with a border of sentinels (square
-- (r, c) is r * 10 + c) and plays/undoes moves in place, instead of copying
-- the 8x8 grid at every node. Evaluation is unchanged and still from black's
-- perspective; negamax just flips its sign for white.
-- ---------------------------------------------------------------------------

-- Scales every time budget. A test harness sets it below 1 to reproduce on
-- a desktop the depth an e-reader CPU (~25x slower) reaches in the budget.
OthelloBoard.AI_TIME_SCALE = 1

local clock = os.clock

local EDGE  = 3          -- sentinel value around the board
local FDIRS = { -11, -10, -9, -1, 1, 9, 10, 11 }

-- Positional bonus per square, exactly as before: corners 30, edges 5.
local SQ_BONUS = {}
for r = 1, 8 do
    for c = 1, 8 do
        local b = 0
        if CORNER_SET[r * 10 + c] then b = 30
        elseif r == 1 or r == 8 or c == 1 or c == 8 then b = 5 end
        SQ_BONUS[r * 10 + c] = b
    end
end

-- Squares in row-major order (the order the old engine tried moves in, which
-- is also its tie-break between equally good moves).
local SQUARES = {}
for r = 1, 8 do
    for c = 1, 8 do SQUARES[#SQUARES + 1] = r * 10 + c end
end

-- Move-ordering priority: corners first, then edges and the centre, the
-- squares next to a corner last. Only affects speed, never the result.
local ORDER_W = {
    { 100, -20, 10,  5,  5, 10, -20, 100 },
    { -20, -50, -2, -2, -2, -2, -50, -20 },
    {  10,  -2,  1,  1,  1,  1,  -2,  10 },
    {   5,  -2,  1,  0,  0,  1,  -2,   5 },
    {   5,  -2,  1,  0,  0,  1,  -2,   5 },
    {  10,  -2,  1,  1,  1,  1,  -2,  10 },
    { -20, -50, -2, -2, -2, -2, -50, -20 },
    { 100, -20, 10,  5,  5, 10, -20, 100 },
}
local ORDER = {}
for i = 1, 64 do ORDER[i] = SQUARES[i] end
table.sort(ORDER, function(a, b)
    local wa = ORDER_W[math.floor(a / 10)][a % 10]
    local wb = ORDER_W[math.floor(b / 10)][b % 10]
    if wa ~= wb then return wa > wb end
    return a < b
end)

-- Search state (one search at a time).
local deadline  -- os.clock() value at which to stop, or nil (no limit)
local aborted = false
local nodes   = 0
local fstack  = {}   -- squares flipped by the moves currently played
local fsp     = 0

local function timeUp()
    nodes = nodes + 1
    if deadline and nodes % 256 == 0 and clock() > deadline then
        aborted = true
    end
    return aborted
end

local function isLegal(b, sq, me, op)
    for k = 1, 8 do
        local d = FDIRS[k]
        local p = sq + d
        if b[p] == op then
            p = p + d
            while b[p] == op do p = p + d end
            if b[p] == me then return true end
        end
    end
    return false
end

-- Legal moves of `me`, in ORDER; returns the list and its length.
local function genMoves(b, me, op)
    local moves, n = {}, 0
    for i = 1, 64 do
        local sq = ORDER[i]
        if b[sq] == 0 and isLegal(b, sq, me, op) then
            n = n + 1
            moves[n] = sq
        end
    end
    return moves, n
end

local function hasMove(b, me, op)
    for i = 1, 64 do
        local sq = SQUARES[i]
        if b[sq] == 0 and isLegal(b, sq, me, op) then return true end
    end
    return false
end

local function countMoves(b, me, op)
    local n = 0
    for i = 1, 64 do
        local sq = SQUARES[i]
        if b[sq] == 0 and isLegal(b, sq, me, op) then n = n + 1 end
    end
    return n
end

-- Plays `me` on sq; returns how many discs flipped (pushed on fstack).
local function makeMove(b, sq, me, op)
    local n = 0
    for k = 1, 8 do
        local d = FDIRS[k]
        local p = sq + d
        if b[p] == op then
            p = p + d
            while b[p] == op do p = p + d end
            if b[p] == me then
                p = sq + d
                while b[p] == op do
                    b[p] = me
                    fsp = fsp + 1
                    fstack[fsp] = p
                    n = n + 1
                    p = p + d
                end
            end
        end
    end
    b[sq] = me
    return n
end

local function unmakeMove(b, sq, n, op)
    b[sq] = 0
    for _ = 1, n do
        b[fstack[fsp]] = op
        fsp = fsp - 1
    end
end

-- Static evaluation from black's perspective: disc difference, corner/edge
-- bonuses and 2 x mobility difference (unchanged from the grid version).
local function evaluate(b)
    local score = 0
    for i = 1, 64 do
        local sq = SQUARES[i]
        local v = b[sq]
        if v == BLACK then
            score = score + 1 + SQ_BONUS[sq]
        elseif v == WHITE then
            score = score - 1 - SQ_BONUS[sq]
        end
    end
    return score + (countMoves(b, BLACK, WHITE) - countMoves(b, WHITE, BLACK)) * 2
end

-- Near the end there is no need to guess: the remaining tree is small enough
-- to search to the last disc and play the move that provably wins. Below this
-- many empty squares the engine stops evaluating and starts proving.
-- 10, not more. At 13 the engine plays marginally better but one move took
-- 10.8s on a desktop, which on an e-ink CPU is a minute of staring at the
-- board. The solve also runs under the time budget now: if it cannot finish,
-- the move comes from the heuristic search instead.
local ENDGAME_EMPTIES = 10

-- Final disc difference from black's perspective. Scaled well clear of
-- evaluate's range so a proven result always outranks a guessed one.
local ENDGAME_SCALE = 100000

local function finalScore(b)
    local d = 0
    for i = 1, 64 do
        local v = b[SQUARES[i]]
        if v == BLACK then d = d + 1 elseif v == WHITE then d = d - 1 end
    end
    return d * ENDGAME_SCALE
end

local function sideSign(me) return me == BLACK and 1 or -1 end

-- Negamax: value for the side to move (`me`). depth < 0 means "play it out
-- to the end" (exact endgame solve, no evaluation).
local function search(b, me, op, depth, alpha, beta)
    if timeUp() then return 0 end
    if depth == 0 then return sideSign(me) * evaluate(b) end

    local moves, n = genMoves(b, me, op)
    if n == 0 then
        if not hasMove(b, op, me) then
            -- Nobody can move: the game is over.
            if depth < 0 then return sideSign(me) * finalScore(b) end
            return sideSign(me) * evaluate(b)
        end
        -- Pass: the opponent plays (a pass costs a ply of depth).
        return -search(b, op, me, depth < 0 and depth or depth - 1, -beta, -alpha)
    end

    -- Far from the leaves, try first the moves that leave the opponent the
    -- fewest replies: they are the likeliest to cut the rest off.
    if n > 1 and (depth >= 3 or depth < 0) then
        local key = {}
        for i = 1, n do
            local sq = moves[i]
            local nf = makeMove(b, sq, me, op)
            key[sq] = countMoves(b, op, me) * 128 + i
            unmakeMove(b, sq, nf, op)
        end
        table.sort(moves, function(x, y) return key[x] < key[y] end)
    end

    local best = -INF
    local child = depth < 0 and depth or depth - 1
    for i = 1, n do
        local sq = moves[i]
        local nf = makeMove(b, sq, me, op)
        local v = -search(b, op, me, child, -beta, -alpha)
        unmakeMove(b, sq, nf, op)
        if aborted then return 0 end
        if v > best then
            best = v
            if v > alpha then
                alpha = v
                if alpha >= beta then break end
            end
        end
    end
    return best
end

-- One root iteration at `depth` (-1 = exact). `root` is the move list in
-- search order (best of the previous iteration first). Ties are broken
-- towards the lowest row-major square, like the old fixed-depth engine, so
-- an unbudgeted search plays exactly the move it used to.
-- Returns the best square of the moves fully searched (nil if none), and
-- whether every move was searched.
-- noise > 0: every move that could still be picked once a bonus below
-- `noise` is added gets its exact score, not just a bound (moves more than
-- `noise` below the best cannot be picked, so they keep a cheap bound).
local function searchRoot(b, me, op, root, depth, noise)
    local best_sq, best_v = nil, -INF
    local scores = {}
    for i = 1, #root do
        local sq = root[i]
        local nf = makeMove(b, sq, me, op)
        -- A square that would win a tie must prove it ties: search it with
        -- a window one point lower so an equal score comes back exact.
        local a = best_v
        if best_sq and sq < best_sq then a = best_v - 1 end
        if noise > 0 then a = best_v - noise end
        local v = -search(b, op, me, depth < 0 and depth or depth - 1, -INF, -a)
        unmakeMove(b, sq, nf, op)
        if aborted then return best_sq, false, scores end
        scores[sq] = v
        if v > best_v or (v == best_v and best_sq and sq < best_sq) then
            best_v, best_sq = v, sq
        end
    end
    return best_sq, true, scores
end

-- Reorders root moves: best first, then by last iteration's score.
local function reorderRoot(root, scores, best_sq)
    table.sort(root, function(x, y)
        if x == best_sq then return y ~= best_sq end
        if y == best_sq then return false end
        local sx, sy = scores[x] or -INF, scores[y] or -INF
        if sx ~= sy then return sx > sy end
        return false
    end)
end

-- ---------------------------------------------------------------------------
-- Difficulty levels.
-- depth:   deepest iteration of the heuristic search.
-- budget:  thinking time in seconds on the e-reader (CPU time, so a slower
--          device searches less deep instead of taking longer).
-- noise:   a random bonus in [0, noise) added to each move's score before
--          choosing, so a level does not answer a line the same way every
--          game (a corner is worth 30, a disc 1).
-- endgame: number of empty squares from which the position is played out
--          exactly to the last disc (0 = never).
-- Measured (Kobo-scaled budgets, randomised openings): Easy scores about
-- 50% against a 1-ply greedy player, Medium about 95% against Easy and
-- Hard about 70% against Medium.
-- ---------------------------------------------------------------------------

OthelloBoard.LEVELS = {
    easy   = { depth = 2, budget = 0.5, noise = 100, endgame = 0 },
    medium = { depth = 4, budget = 1.0, noise = 6,  endgame = 10 },
    hard   = { depth = 6, budget = 2.2, noise = 0,  endgame = 10 },
}

-- ---------------------------------------------------------------------------
-- getAIMove — returns {r, c} or nil
-- depth:  maximum search depth (the difficulty level).
-- budget: seconds of thinking allowed (on the e-reader), or nil for no
--         limit. Search deepens one ply at a time up to `depth` and keeps
--         the best move of the deepest iteration that had time to finish.
-- opts:   optional { noise, endgame, rng } (see LEVELS; rng defaults to
--         math.random). Without opts: no noise, exact endgame from 10.
-- ---------------------------------------------------------------------------

function OthelloBoard:getAIMove(depth, budget, opts)
    depth = depth or 4
    opts = opts or {}
    local noise = opts.noise or 0
    local endgame = opts.endgame or ENDGAME_EMPTIES
    local rng = opts.rng or math.random
    local me = colorVal(self.turn)
    local op = oppVal(me)

    -- Flat copy of the grid.
    local b = {}
    for i = 0, 99 do b[i] = EDGE end
    for r = 1, 8 do
        for c = 1, 8 do b[r * 10 + c] = self.grid[r][c] end
    end

    local root = genMoves(b, me, op)
    if #root == 0 then return nil end

    local start = clock()
    deadline = budget and (start + budget * OthelloBoard.AI_TIME_SCALE) or nil
    aborted, nodes, fsp = false, 0, 0

    -- Fallback if not even depth 1 finishes: the best-ordered legal move.
    local best_sq = root[1]
    self.ai_depth = 0

    local empties = 0
    for i = 1, 64 do
        if b[SQUARES[i]] == 0 then empties = empties + 1 end
    end

    -- Once few enough squares are left, play it out exactly instead of
    -- evaluating: the answer stops being an opinion. It gets most of the
    -- budget; if it runs out, the heuristic search below takes over.
    if empties <= endgame then
        if budget then
            deadline = start + budget * 0.7 * OthelloBoard.AI_TIME_SCALE
        end
        local sq, complete = searchRoot(b, me, op, root, -1, 0)
        if complete then
            self.ai_depth = -1
            local r = math.floor(sq / 10)
            return { r, sq - r * 10 }
        end
        aborted, fsp = false, 0
        if budget then
            deadline = start + budget * OthelloBoard.AI_TIME_SCALE
        end
        b = {}
        for i = 0, 99 do b[i] = EDGE end
        for r = 1, 8 do
            for c = 1, 8 do b[r * 10 + c] = self.grid[r][c] end
        end
    end

    local exact = noise > 0
    local final_scores
    for d = 1, depth do
        local sq, complete, scores = searchRoot(b, me, op, root, d, noise)
        if complete then
            best_sq = sq
            self.ai_depth = d
            final_scores = scores
            reorderRoot(root, scores, sq)
        elseif exact then
            break
        else
            -- The previous best is searched first, so any move that beat it
            -- in this unfinished iteration is a better-informed choice.
            if sq and scores[root[1]] then best_sq = sq end
            break
        end
    end

    -- Noise: pick the move with the best score plus a random bonus, from the
    -- deepest iteration that searched every move.
    if exact and final_scores then
        local best_v = -INF
        for i = 1, #root do
            local sq = root[i]
            local v = final_scores[sq] + rng() * noise
            if v > best_v then best_v, best_sq = v, sq end
        end
    end

    local r = math.floor(best_sq / 10)
    return { r, best_sq - r * 10 }
end


-- ---------------------------------------------------------------------------
-- applyAIMove — apply best AI move
-- Returns "ok", "skip", "ended", or "none" (no moves available)
-- ---------------------------------------------------------------------------

function OthelloBoard:applyAIMove(depth, budget, opts)
    local move = self:getAIMove(depth, budget, opts)
    if not move then
        -- AI has no valid move — this shouldn't happen if called at the right time,
        -- but handle it gracefully by advancing the turn
        return self:_advanceTurn()
    end
    return self:placeDisk(move[1], move[2])
end

return OthelloBoard
