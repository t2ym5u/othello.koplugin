-- ---------------------------------------------------------------------------
-- OthelloScreen — full-screen UI for Othello/Reversi
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper  = require("menu_helper")
local ScreenBase  = require("screen_base")

local OthelloBoard       = lrequire("board")
local OthelloBoardWidget = lrequire("board_widget")

-- Difficulty → minimax depth
local DIFF_DEPTH = { easy = 2, medium = 4, hard = 6 }

-- ---------------------------------------------------------------------------
-- OthelloScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Othello (Reversi) — Rules

Two players alternate placing discs on the board.

When you place a disc, any straight line (horizontal, vertical, or diagonal) of opponent discs bounded between your new disc and one of your existing discs is flipped to your colour.

Rules:
• You must flip at least one opponent disc per move.
• If you have no valid move, your turn is skipped.
• The game ends when the board is full or neither player can move.

The player with the most discs of their colour at the end wins.
]])

local GAME_RULES_FR = [[
Othello (Reversi) — Règles

Les deux joueurs placent alternativement des pions sur le plateau.

Quand vous placez un pion, toute ligne droite (horizontale, verticale ou diagonale) de pions adverses encadrée entre votre nouveau pion et un de vos pions existants est retournée à votre couleur.

Règles :
• Vous devez retourner au moins un pion adverse par coup.
• Si vous n'avez aucun coup valide, votre tour est passé.
• La partie se termine quand le plateau est plein ou qu'aucun joueur ne peut jouer.

Le joueur ayant le plus de pions de sa couleur à la fin gagne.
]]

local OthelloScreen = ScreenBase:extend{}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function OthelloScreen:init()
    local state   = self.plugin:loadState()
    self.board    = OthelloBoard:new()
    if not self.board:load(state) then
        self.board:reset()
    end
    ScreenBase.init(self)  -- calls buildLayout()
    -- Trigger AI if it's the AI's first turn
    if self:_isAITurn() then
        UIManager:scheduleIn(0.1, function() self:triggerAI() end)
    end
end

-- A full board, or neither side able to move, ends the game.
function OthelloScreen:isRoundOver()
    return self.board.status ~= "playing"
end

function OthelloScreen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function OthelloScreen:buildLayout()
    local is_landscape = self:isLandscape()

    -- Title bar with Options menu
    local title_bar = self:buildTitleBar(_("Othello"), function()
        local items = {
            { text = _("New game"),                 callback = function() self:onNewGame() end },
            { text = self:_getDiffButtonText(),     callback = function() self:openDifficultyMenu() end },
            { text = self:_getPlayersButtonText(),  callback = function() self:openPlayersMenu() end },
        }
        -- The colour choice only means something against the AI.
        if self.plugin:getSetting("players", 1) == 1 then
            items[#items + 1] = { text = self:_getColorButtonText(),
                                  callback = function() self:openColorMenu() end }
        end
        items[#items + 1] = self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR)
        return items
    end)

    local controls_w = self:getControlsWidth()
    self.status_text:setMaxWidth(controls_w)
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar({
            { text = _("Pass"), callback = function() self:onPass() end },
        }),
    }

    -- The widget paints its own thick outer border, so the frame only pads.
    local frame_pad = Size.padding.default
    local frame_extra = 2 * frame_pad
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = OthelloBoardWidget:new{
        board        = self.board,
        max_size     = math.min(budget_w, budget_h) - frame_extra,
        onCellAction = function(r, c) self:onCellAction(r, c) end,
    }
    local board_frame = FrameContainer:new{
        padding    = frame_pad,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Helpers: is it the AI's turn?
-- ---------------------------------------------------------------------------

function OthelloScreen:_isAITurn()
    if self.board.status ~= "playing" then return false end
    local players = self.plugin:getSetting("players", 1)
    if players ~= 1 then return false end
    local player_color = self.plugin:getSetting("player_color", "black")
    -- AI plays the opposite color from the human player
    local ai_color = (player_color == "black") and "white" or "black"
    return self.board.turn == ai_color
end

-- ---------------------------------------------------------------------------
-- Cell interaction
-- ---------------------------------------------------------------------------

function OthelloScreen:onCellAction(r, c)
    local board = self.board
    if board.status ~= "playing" then return end

    -- In 1-player mode, only accept input when it's the human's turn
    if not self:_isHumanTurn() then return end

    local result = board:placeDisk(r, c)

    if result == "invalid" then
        return  -- ignore invalid taps silently

    elseif result == "ok" then
        self.board_widget:refresh()
        self.plugin:saveState(self:serializeState())
        self:updateStatus()
        if self:_isAITurn() then
            self:triggerAI()
        end

    elseif result == "skip" then
        -- Current player's turn was preserved (opponent had no moves)
        self.board_widget:refresh()
        self.plugin:saveState(self:serializeState())
        self:showMessage(_("Opponent passes their turn!"), 2)
        self:updateStatus()
        -- Check if AI would still need to play (shouldn't happen in skip case,
        -- but handle edge cases)
        if self:_isAITurn() then
            self:triggerAI()
        end

    elseif result == "ended" then
        self.board_widget:refresh()
        self.plugin:saveState(self:serializeState())
        self:updateStatus()
        self:onGameEnd()
    end
end

-- In 1-player mode: returns true if it's the human player's turn.
-- In 2-player mode: always true.
function OthelloScreen:_isHumanTurn()
    local players = self.plugin:getSetting("players", 1)
    if players ~= 1 then return true end
    local player_color = self.plugin:getSetting("player_color", "black")
    return self.board.turn == player_color
end

-- ---------------------------------------------------------------------------
-- Pass button — manually skip turn (for 2P or when stuck)
-- ---------------------------------------------------------------------------

function OthelloScreen:onPass()
    local board = self.board
    if board.status ~= "playing" then return end

    local valid = board:getValidMoves(board.turn)
    if #valid > 0 then
        self:showMessage(_("You have valid moves available!"), 2)
        return
    end

    -- No valid moves: the player must pass
    -- Simulate by calling _advanceTurn directly
    local result = board:_advanceTurn()
    self.board_widget:refresh()
    self.plugin:saveState(self:serializeState())
    self:updateStatus()

    if result == "ended" then
        self:onGameEnd()
    elseif self:_isAITurn() then
        self:triggerAI()
    end
end

-- ---------------------------------------------------------------------------
-- AI
-- ---------------------------------------------------------------------------

function OthelloScreen:triggerAI()
    if self.board.status ~= "playing" then return end
    if not self:_isAITurn() then return end

    self:updateStatus(_("AI is thinking..."))
    local diff  = self.plugin:getSetting("difficulty", "medium")
    local depth = DIFF_DEPTH[diff] or 4

    UIManager:scheduleIn(0.05, function()
        if self.board.status ~= "playing" then return end

        local result = self.board:applyAIMove(depth)
        self.board_widget:refresh()
        self.plugin:saveState(self:serializeState())

        if result == "ended" then
            self:updateStatus()
            self:onGameEnd()
        elseif result == "skip" then
            -- AI's turn was kept because opponent (human) had no moves
            self:showMessage(_("You have no valid move, the AI plays again!"), 2)
            self:updateStatus()
            -- AI plays again (schedule to avoid deep recursion)
            UIManager:scheduleIn(0.5, function() self:triggerAI() end)
        else
            self:updateStatus()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- New game
-- ---------------------------------------------------------------------------

function OthelloScreen:onNewGame()
    self.board = OthelloBoard:new()
    self.board:reset()
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    if self:_isAITurn() then
        UIManager:scheduleIn(0.1, function() self:triggerAI() end)
    end
end

-- ---------------------------------------------------------------------------
-- Game end
-- ---------------------------------------------------------------------------

function OthelloScreen:onGameEnd()
    local board = self.board
    local bc, wc = board:countDiscs()
    local msg
    if board.winner == "black" then
        msg = string.format(_("Black wins! %d - %d"), bc, wc)
    elseif board.winner == "white" then
        msg = string.format(_("White wins! %d - %d"), wc, bc)
    else
        msg = string.format(_("Tie! %d - %d"), bc, wc)
    end
    self:showMessage(msg, 4)
end

-- ---------------------------------------------------------------------------
-- Status bar
-- ---------------------------------------------------------------------------

function OthelloScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board.status == "ended" then
        local bc, wc = self.board:countDiscs()
        local winner = self.board.winner
        if winner == "black" then
            status = string.format(_("Black wins! Black: %d  White: %d"), bc, wc)
        elseif winner == "white" then
            status = string.format(_("White wins! Black: %d  White: %d"), bc, wc)
        else
            status = string.format(_("Tie! Black: %d  White: %d"), bc, wc)
        end
    else
        local bc, wc  = self.board:countDiscs()
        local turn    = (self.board.turn == "black") and _("Black") or _("White")
        local dlabel
        if self.plugin:getSetting("players", 1) == 1 then
            local diff = self.plugin:getSetting("difficulty", "medium")
            dlabel = MenuHelper.DIFFICULTY_LABELS[diff] or diff
        end
        status = self:joinStatus(
            T("%1×%1", 8),
            dlabel,
            T(_("%1 to move"), turn),
            T(_("Black: %1"), bc),
            T(_("White: %1"), wc))
    end
    ScreenBase.updateStatus(self, status)
    -- Every move and pass (player's or AI's) ends here.
    self:refreshActionBar()
end

-- ---------------------------------------------------------------------------
-- Button label helpers
-- ---------------------------------------------------------------------------

function OthelloScreen:_getPlayersButtonText()
    return T(_("Players: %1"), self.plugin:getSetting("players", 1))
end

function OthelloScreen:_getColorButtonText()
    local pcol = self.plugin:getSetting("player_color", "black")
    return T(_("Play as: %1"), (pcol == "black") and _("Black") or _("White"))
end

function OthelloScreen:_getDiffButtonText()
    local diff   = self.plugin:getSetting("difficulty", "medium")
    return T(_("Difficulty: %1"), MenuHelper.DIFFICULTY_LABELS[diff] or diff)
end

-- ---------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------

function OthelloScreen:openPlayersMenu()
    MenuHelper.openPickerMenu{
        title      = _("Players"),
        items      = {
            { id = 1, text = _("1 player (vs AI)") },
            { id = 2, text = _("2 players") },
        },
        current_id = self.plugin:getSetting("players", 1),
        on_select  = function(id)
            self.plugin:saveSetting("players", id)
            local btn = self.top_buttons and self.top_buttons:getButtonById("players_btn")
            if btn then btn:setText(self:_getPlayersButtonText(), btn.width) end
            -- Also update the color button label visibility
            local cbtn = self.top_buttons and self.top_buttons:getButtonById("color_btn")
            if cbtn then cbtn:setText(self:_getColorButtonText(), cbtn.width) end
            self:updateStatus()
        end,
        parent = self,
    }
end

function OthelloScreen:openColorMenu()
    local players = self.plugin:getSetting("players", 1)
    if players ~= 1 then
        self:showMessage(_("Only available in 1-player mode."), 2)
        return
    end
    MenuHelper.openPickerMenu{
        title      = _("Play as"),
        items      = {
            { id = "black", text = _("Black (plays first)") },
            { id = "white", text = _("White (plays second)") },
        },
        current_id = self.plugin:getSetting("player_color", "black"),
        on_select  = function(id)
            self.plugin:saveSetting("player_color", id)
            local btn = self.top_buttons and self.top_buttons:getButtonById("color_btn")
            if btn then btn:setText(self:_getColorButtonText(), btn.width) end
            self:updateStatus()
            -- Start a new game with the new color assignment
            self:onNewGame()
        end,
        parent = self,
    }
end

function OthelloScreen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "medium"),
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            local btn = self.top_buttons and self.top_buttons:getButtonById("diff_btn")
            if btn then btn:setText(self:_getDiffButtonText(), btn.width) end
            self:updateStatus()
        end,
        parent = self,
    }
end

return OthelloScreen
