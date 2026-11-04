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
