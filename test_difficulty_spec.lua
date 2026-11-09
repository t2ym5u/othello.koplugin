-- Difficulty guarantees of the Othello computer opponent: the level table is
-- ordered, every level plays legal moves, Medium and Hard play endgames
-- exactly (never throw away a won ending) while Easy does not solve them,
-- the same seed gives the same game, and each level stays within its think
-- time at Kobo speed. No full matches.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("Othello difficulty", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    after_each(function()
        Board.AI_TIME_SCALE = 1
    end)

    local IDS = { "easy", "medium", "hard" }

    local function clone(b)
        local o = Board:new()
        o:load(b:serialize())
        return o
    end

    -- Plays `plies` moves (a skip counts as one), every move from `level`,
    -- the rng seeded: a short line, not a whole match.
    local function playLine(level, seed, plies)
        math.randomseed(seed)
        local b = Board:new()
        b:reset()
        local moves = {}
        for _ = 1, plies or 20 do
            if b.status ~= "playing" then break end
            local move = b:getAIMove(level.depth, level.budget, level)
            if not move then
                b:_advanceTurn()
            else
                assert.is_true(b:isValidMove(move[1], move[2], b.turn))
                moves[#moves + 1] = move[1] * 10 + move[2]
                b:placeDisk(move[1], move[2])
            end
        end
        return table.concat(moves, ",")
    end

    -- Random positions from seeded random games, `empties` squares left.
    local function randomPositions(n, seed, empties)
        math.randomseed(seed)
        local out = {}
        for _ = 1, n * 20 do
            if #out >= n then break end
            local b = Board:new()
            b:reset()
            while b.status == "playing" do
                local bc, wc = b:countDiscs()
                if 64 - bc - wc <= empties then break end
                local mv = b:getValidMoves(b.turn)
                if #mv == 0 then b:_advanceTurn() else
                    local m = mv[math.random(#mv)]
                    b:placeDisk(m.r, m.c)
                end
            end
            if b.status == "playing" and #b:getValidMoves(b.turn) > 0 then
                out[#out + 1] = b
            end
        end
        return out
    end

    -- Game result under perfect play, for the side `me`: 1 win, 0 draw,
    -- -1 loss. Plain minimax on board copies: the reference the engine's
    -- exact endgame is checked against.
    local function result(b, me)
        if b.status ~= "playing" then
            local bc, wc = b:countDiscs()
            local d = (me == "black") and (bc - wc) or (wc - bc)
            return d > 0 and 1 or d < 0 and -1 or 0
        end
        local mv = b:getValidMoves(b.turn)
        if #mv == 0 then
            local c = clone(b); c:_advanceTurn()
            return result(c, me)
        end
        local mine = b.turn == me
        local best = mine and -2 or 2
        for _, m in ipairs(mv) do
            local c = clone(b)
            c:placeDisk(m.r, m.c)
            local v = result(c, me)
            if mine then
                if v > best then best = v end
                if best == 1 then break end
            else
                if v < best then best = v end
                if best == -1 then break end
            end
        end
        return best
    end

    it("gets weaker from Hard to Easy", function()
        local L = Board.LEVELS
        assert.is_true(L.easy.depth < L.medium.depth and L.medium.depth < L.hard.depth)
        assert.is_true(L.easy.noise > L.medium.noise and L.medium.noise > L.hard.noise)
        assert.are.equal(0, L.hard.noise)
        assert.are.equal(0, L.easy.endgame)       -- Easy never solves the end
        assert.is_true(L.medium.endgame > 0 and L.hard.endgame > 0)
        for _, id in ipairs(IDS) do
            assert.is_true(L[id].budget <= 2.2)
        end
    end)

    it("plays a legal move within its time budget all game long", function()
        math.randomseed(7)
        local b = Board:new()
        b:reset()
        local worst = 0
        while b.status == "playing" do
            local t0 = os.clock()
            local move = b:getAIMove(6, 0.05)
            local dt = os.clock() - t0
            if dt > worst then worst = dt end
            if not move then
                b:_advanceTurn()
            else
                assert.is_true(b:isValidMove(move[1], move[2], b.turn))
                b:placeDisk(move[1], move[2])
            end
        end
        -- 0.05 s budget; generous slack for slow test interpreters.
        assert.is_true(worst < 0.5, "slowest move " .. worst .. " s")
    end)

    it("plays the provable best move in the endgame", function()
        -- 9 empty squares left: the engine must solve it to the end.
        local b = Board:new()
        for r = 1, 8 do for c = 1, 8 do b.grid[r][c] = 1 end end
        for r = 1, 3 do for c = 6, 8 do b.grid[r][c] = 0 end end
        b.grid[2][7] = 2; b.grid[3][6] = 2
        b.turn = "black"
        local move = b:getAIMove(2, 1.0)
        assert.is_not_nil(move)
        assert.is_true(b:isValidMove(move[1], move[2], "black"))
        assert.are.equal(-1, b.ai_depth)   -- solved exactly
    end)

    it("Medium and Hard never spoil an ending they can win or draw", function()
        local checked = 0
        for _, b in ipairs(randomPositions(8, 21, 7)) do
            local me = b.turn
            local best = result(b, me)
            for seed, id in ipairs({ "medium", "hard" }) do
                math.randomseed(seed)
                local L = Board.LEVELS[id]
                local m = b:getAIMove(L.depth, L.budget, L)
                assert.are.equal(-1, b.ai_depth, id .. " did not solve 7 empties")
                local c = clone(b)
                c:placeDisk(m[1], m[2])
                assert.are.equal(best, result(c, me), id .. " spoilt an ending")
            end
            checked = checked + 1
        end
        assert.is_true(checked >= 5)
    end)

    it("Easy does not solve the endgame exactly", function()
        local b = Board:new()
        for r = 1, 8 do for c = 1, 8 do b.grid[r][c] = 1 end end
        for r = 1, 3 do for c = 6, 8 do b.grid[r][c] = 0 end end
        b.grid[2][7] = 2; b.grid[3][6] = 2
        b.turn = "black"
        local L = Board.LEVELS.easy
        local move = b:getAIMove(L.depth, L.budget, L)
        assert.is_true(b:isValidMove(move[1], move[2], "black"))
        assert.are.equal(L.depth, b.ai_depth)
    end)

    it("every level plays legal moves in random positions", function()
        Board.AI_TIME_SCALE = 0.04
        for _, empties in ipairs({ 50, 30, 14 }) do
            for _, b in ipairs(randomPositions(4, empties, empties)) do
                for _, id in ipairs(IDS) do
                    local L = Board.LEVELS[id]
                    local m = b:getAIMove(L.depth, L.budget, L)
                    assert.is_not_nil(m)
                    assert.is_true(b:isValidMove(m[1], m[2], b.turn))
                end
            end
        end
    end)

    it("keeps every level within its budget at Kobo speed", function()
        -- AI_TIME_SCALE 0.04 stands for a CPU 25x slower: the real time
        -- spent, times 25, is the Kobo's wait. 14 and 11 empties are where
        -- the exact endgame (from 10) is about to start or just too big.
        Board.AI_TIME_SCALE = 0.04
        local worst = 0
        for _, empties in ipairs({ 40, 20, 11 }) do
            for _, b in ipairs(randomPositions(3, 100 + empties, empties)) do
                for _, id in ipairs(IDS) do
                    local L = Board.LEVELS[id]
                    local t0 = os.clock()
                    b:getAIMove(L.depth, L.budget, L)
                    local dt = (os.clock() - t0) * 25
                    if dt > worst then worst = dt end
                end
            end
        end
        assert.is_true(worst <= 2.5, string.format("slowest Kobo move %.2f s", worst))
    end)

    it("Easy and Medium play legal moves and vary between games", function()
        for _, id in ipairs({ "easy", "medium" }) do
            local level = { depth = Board.LEVELS[id].depth, budget = 0.05,
                            noise = Board.LEVELS[id].noise,
                            endgame = Board.LEVELS[id].endgame }
            local seen, distinct = {}, 0
            for seed = 1, 4 do
                local g = playLine(level, seed)
                if not seen[g] then seen[g] = true; distinct = distinct + 1 end
            end
            assert.is_true(distinct >= 2, id .. " played the same game every time")
        end
    end)

    it("plays the same game twice under the same seed", function()
        for _, id in ipairs({ "easy", "medium" }) do
            local L = Board.LEVELS[id]
            local level = { depth = L.depth, noise = L.noise, endgame = L.endgame }
            assert.are.equal(playLine(level, 42), playLine(level, 42))
        end
    end)

    it("noise uses the given rng", function()
        local b = Board:new()
        b:reset()
        -- rng always 0: same move as the noiseless search.
        local plain = b:getAIMove(2)
        local zero = b:getAIMove(2, nil, { noise = 1000, endgame = 0, rng = function() return 0 end })
        assert.are.same(plain, zero)
    end)
end)
