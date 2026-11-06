local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("OthelloBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    describe("new / reset", function()
        it("new() starts with an empty board", function()
            local b = Board:new()
            for r = 1, 8 do
                for c = 1, 8 do
                    assert.are.equal(0, b.grid[r][c])
                end
            end
        end)

        it("reset() sets up the standard 4-disc starting position", function()
            local b = Board:new()
            b:reset()
            assert.are.equal(2, b.grid[4][4])  -- white
            assert.are.equal(1, b.grid[4][5])  -- black
            assert.are.equal(1, b.grid[5][4])  -- black
            assert.are.equal(2, b.grid[5][5])  -- white
            assert.are.equal("black", b.turn)
            assert.are.equal("playing", b.status)
        end)
    end)

    describe("getValidMoves / isValidMove", function()
        it("black has exactly 4 legal opening moves", function()
            local b = Board:new()
            b:reset()
            local moves = b:getValidMoves("black")
            assert.are.equal(4, #moves)
            local expected = { ["3,4"]=true, ["4,3"]=true, ["5,6"]=true, ["6,5"]=true }
            for _, m in ipairs(moves) do
                assert.is_true(expected[m.r .. "," .. m.c])
            end
        end)
    end)

    describe("placeDisk", function()
        it("flips the bracketed opponent disc and switches turn", function()
            local b = Board:new()
            b:reset()
            assert.are.equal("ok", b:placeDisk(3, 4))  -- black plays d3
            assert.are.equal(1, b.grid[3][4])
            assert.are.equal(1, b.grid[4][4])  -- flipped from white to black
            assert.are.equal("white", b.turn)
        end)

        it("rejects a move that flips nothing", function()
            local b = Board:new()
            b:reset()
            assert.are.equal("invalid", b:placeDisk(1, 1))
        end)
    end)

    describe("countDiscs", function()
        it("counts 2 black and 2 white at the start", function()
            local b = Board:new()
            b:reset()
            local black, white = b:countDiscs()
            assert.are.equal(2, black)
            assert.are.equal(2, white)
        end)
    end)

    describe("getAIMove", function()
        it("returns a currently-valid move for the side to play", function()
            local b = Board:new()
            b:reset()
            local move = b:getAIMove(2)
            assert.is_not_nil(move)
            assert.is_true(b:isValidMove(move[1], move[2], b.turn))
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

        it("still returns a legal move when no iteration can finish", function()
            local b = Board:new()
            b:reset()
            b:placeDisk(3, 4); b:placeDisk(3, 3); b:placeDisk(4, 3)
            local move = b:getAIMove(6, 1e-9)
            assert.is_not_nil(move)
            assert.is_true(b:isValidMove(move[1], move[2], b.turn))
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
    end)

    describe("difficulty levels", function()
        -- Plays a whole game, every move from `level`, the rng seeded.
        local function playGame(level, seed)
            math.randomseed(seed)
            local b = Board:new()
            b:reset()
            local moves = {}
            while b.status == "playing" do
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

        it("gets weaker from Hard to Easy", function()
            local L = Board.LEVELS
            assert.is_true(L.easy.depth < L.medium.depth and L.medium.depth < L.hard.depth)
            assert.is_true(L.easy.noise > L.medium.noise and L.medium.noise > L.hard.noise)
            assert.are.equal(0, L.hard.noise)
            assert.are.equal(0, L.easy.endgame)       -- Easy never solves the end
            assert.is_true(L.medium.endgame > 0 and L.hard.endgame > 0)
            for _, id in ipairs({ "easy", "medium", "hard" }) do
                assert.is_true(L[id].budget <= 2.2)
            end
        end)

        it("Easy and Medium play legal moves and vary between games", function()
            for _, id in ipairs({ "easy", "medium" }) do
                local level = { depth = Board.LEVELS[id].depth, budget = 0.05,
                                noise = Board.LEVELS[id].noise,
                                endgame = Board.LEVELS[id].endgame }
                local seen, distinct = {}, 0
                for seed = 1, 4 do
                    local g = playGame(level, seed)
                    if not seen[g] then seen[g] = true; distinct = distinct + 1 end
                end
                assert.is_true(distinct >= 2, id .. " played the same game every time")
            end
        end)

        it("plays the same game twice under the same seed", function()
            local L = Board.LEVELS.easy
            local level = { depth = L.depth, noise = L.noise, endgame = L.endgame }
            assert.are.equal(playGame(level, 42), playGame(level, 42))
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

        it("noise uses the given rng", function()
            local b = Board:new()
            b:reset()
            -- rng always 0: same move as the noiseless search.
            local plain = b:getAIMove(2)
            local zero = b:getAIMove(2, nil, { noise = 1000, endgame = 0, rng = function() return 0 end })
            assert.are.same(plain, zero)
        end)
    end)

    describe("serialize / load", function()
        it("round-trips grid, turn and status", function()
            local b = Board:new()
            b:reset()
            b:placeDisk(3, 4)
            local data = b:serialize()

            local b2 = Board:new()
            assert.is_true(b2:load(data))
            assert.are.equal(b.turn, b2.turn)
            for r = 1, 8 do
                for c = 1, 8 do
                    assert.are.equal(b.grid[r][c], b2.grid[r][c])
                end
            end
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
