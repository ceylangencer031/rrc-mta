addEvent("tws-race.onCreatorCreateRace", true)
addEvent("tws-race.onCreatorAddPlayer", true)
addEvent("tws-race.onCreatorRemovePlayer", true)
addEvent("tws-race.onCreatorDrawnLine", true)
addEvent("tws-race.onCreatorAsksForRaceStarting", true)
addEvent("tws-race.onCreatorAbandonRace", true)
addEvent("tws-race.onCreatorToggleBlip", true)
addEvent("tws-race.onClientFinished", true)
addEvent("tws-race.onClientDisqualified", true)
addEvent("tws-message.onClientMessageClick", true)
addEvent("tws-race.onClientInviteResponse", true)

raceManager = {}
raceManager.activeRaces = {}
raceManager.uniqueID = 1

function raceManager:createRace(settings)
	local race = {}
	race.state = "waiting"
	race.players = {}

	-- чекпоинты
	if not settings.checkpoints then
		return false, "no checkpoints"
	end

	if #settings.checkpoints < 3 then
		return false, "#checkpoints < 3"
	end
	race.checkpoints = settings.checkpoints

	-- ид гонки
	self.activeRaces[self.uniqueID] = race
	race.id = self.uniqueID
	self.uniqueID = self.uniqueID + 1

	-- игроки
	if settings.players then
		for _, player in ipairs(settings.players) do
			local a1, a2 = self:addPlayerToRace(player, race.id)
		end
	end

	-- создатель гонки
	if settings.creatorAccount then
		race.creatorAccount = settings.creatorAccount
		race.creator = getPlayerByAccountName(race.creatorAccount)
		race.creator:setData("creator_raceID", race.id)

		if race.creator then
			local text = "Вы успешно создали гонку! (ID: " .. tostring(race.id) .. ")\n\nТеперь вы можете управлять своей\nгонкой. При готовности всех игроков\nначинайте гонку."
			exports["tws-message-manager"]:showMessage(race.creator, "Менеджер создания гонок", text, "ok", 15000, false)
		end
	end

	-- лимит игроков
	race.maxPlayersCount = settings.maxPlayersCount or 32767

	-- можно ли выходить из машины (false по-умолчанию)
	race.leavingVehicleAllowed = settings.leavingVehicleAllowed or false

	-- можно ли менять машину (false по-умолчанию)
	race.changingVehicleAllowed = settings.changingVehicleAllowed or false

	-- отсчет (false по-умолчанию)
	race.countdownEnabled = settings.countdownEnabled or false

	-- заморозка при отсчете (true по-умолчанию)
	race.countdownFreeze = settings.countdownFreeze or true

	-- объявление победителей (false по-умолчанию)
	race.announcingWinnersEnabled = settings.announcingWinnersEnabled or false

	-- через какое время будут объявлены победители?
	race.announcingTimeToWait = settings.announcingTimeToWait or 60000

	-- таблица победителей
	race.winners = {}

	-- создана ли едитолом
	race.isCreatedByEditor = settings.isCreatedByEditor or false

	--outputChatBox("race #" .. tostring(race.id) .. " has just been created")

	return race.id
end

function getPlayerByAccountName(accountName)
	for _, player in ipairs(getElementsByType("player")) do
		if player.account:getName() == accountName then
			return player
		end
	end

	return false
end

function raceManager:startRace(raceID)
	local race = self:getRaceByID(raceID)
	if not race then
		return false, "bad_argument"
	end

	race.state = "running"

	race.maxPlayersCount = #race.players

	-- удаляем блип, если есть
	if race.blip then
		if isElement(race.blip) then
			race.blip:destroy()
		end
		race.blip = nil
	end

	-- замораживаем игроков при отсчете
	if race.countdownEnabled and race.countdownFreeze then
		for _, player in ipairs(race.players) do
			triggerClientEvent(player, "tws-race.onPreStartFreeze", resourceRoot)
		end

		self:freezeRacePlayers(race.id)

		setTimer(
			function()

				self:unfreezeRacePlayers(race.id)
				for _, player in ipairs(race.players) do
					race.startedAt = getTickCount()
					player:setData("tws-race.finished", false)
					triggerClientEvent(player, "tws-race.onRaceStart", root, race)
				end
			end, 4000, 1
		)
	else
		for _, player in ipairs(race.players) do
			race.startedAt = getTickCount()
			player:setData("tws-race.finished", false)
			triggerClientEvent(player, "tws-race.onRaceStart", root, race)
		end
	end

	return true
end

function raceManager:toggleBlip(raceID)
	local race = self:getRaceByID(raceID)
	if not race then
		return
	end

	if not race.blip then
		local x, y, z = race.checkpoints[1].x, race.checkpoints[1].y, race.checkpoints[1].z
		race.blip = createBlip(x, y, z, 53, 2, 0, 0, 255, 255)
	else
		if isElement(race.blip) then
			race.blip:destroy()
		end
		race.blip = nil
	end
end

function raceManager:endRace(raceID)
	local race = self:getRaceByID(raceID)
	if not race then
		return
	end

	-- удаляем блип, если есть
	if race.blip and isElement(race.blip) then
		race.blip:destroy()
	end

	-- удаляет создателя, если таковой имеется
	if race.creatorAccount then
		race.creatorAccount = nil
		race.creator:setData("creator_raceID", false)
		race.creator = nil
	end

	-- чистим дату, триггерим эвент
	for _, player in ipairs(race.players) do
		player:setData("raceID", false)

		triggerClientEvent(player, "tws-race.onClientRaceLeave", resourceRoot)
	end

	race.state = "ended"

	-- удаляем гонку из массива через минуту
	setTimer(
		function()
			raceManager.activeRaces[raceID] = nil
		end, 60000, 1
	)
end

function raceManager:abandonRace(raceID, reason)
	local race = self:getRaceByID(raceID)
	if not race then
		return false
	end

	local text
	if reason == "creator" then
		text = "Создатель гонки отменил гонку."
	elseif reason == "timer" then
		text = "Гонка была отменена по причине отсутствия создателя гонки."
	else
		text = "Гонка была отменена."
	end

	if reason ~= false then
		-- информируем игроков, что гонка отменена
		for _, player in ipairs(race.players) do
			exports["tws-message-manager"]:showMessage(player, "Гонка", text, "race", 10000, true)
		end
	end

	self:endRace(raceID)

	race.state = "abandoned"

	return true
end

function raceManager:getPlayerRace(player)
	if not isElement(player) then
		return false
	end
	local raceID = player:getData("raceID")
	if raceID then
		return raceID
	else
		return false
	end
end

function raceManager:isPlayerInRace(player)
	local raceID = self:getPlayerRace(player)
	if raceID then
		return true
	else
		return false
	end
end

function raceManager:addPlayerToRace(player, raceID)
	-- Если гонки не существует или игрока не существует
	local race = self:getRaceByID(raceID)
	if not race or not isElement(player) then
		return false, "bad argument"
	end
	-- Если гонка не в ожидании
	if race.state ~= "waiting" then
		return false, "race is running"
	end
	-- Если достигнут лимит игроков в гонке
	if #race.players >= (race.maxPlayersCount or 32767) then
		return false, "max players limit"
	end
	-- Находится ли игрок в другой гонке
	local playerRaceID = player:getData("raceID")
	if playerRaceID then
		return false, "already in race"
	end
	-- Добавление игрока в гонку
	table.insert(race.players, player)
	player:setData("raceID", raceID)
	triggerClientEvent(player, "tws-race.onClientRaceJoin", resourceRoot, race.startLine, race.finishLine)
	return true
end

function raceManager:removePlayerFromRace(player, raceID)
	-- Если гонки не существует или игрока не существует
	local race = self:getRaceByID(raceID)
	if not race or not isElement(player) then
		return false, "bad argument"
	end
	-- Есть ли он в этой гонке
	if player:getData("raceID") ~= raceID then
		return false, "player is not in race"
	end
	-- Удаление игрока из гонки
	player:setData("raceID", false)
	for index, racePlayer in ipairs(race.players) do
		if player == racePlayer then
			table.remove(race.players, index)
			break
		end
	end
	triggerClientEvent(player, "tws-race.onClientRaceLeave", resourceRoot)

	-- если все игроки выбыли из гонки
	if #race.players == 0 and race.state == "running" then
		if race.creator then
			exports["tws-message-manager"]:showMessage(race.creator, "Гонка завершена", "Все игроки выбыли из гонки.", "race", false, true)
		end

		self:endRace(raceID)
	end

	return true
end

function raceManager:getRaceByID(raceID)
	return self.activeRaces[raceID]
end

function raceManager:getRaceByCreatorAccount(creatorAccount)
	for _, race in pairs(self.activeRaces) do
		if race.creatorAccount == creatorAccount then
			return race
		end
	end
end

function raceManager:freezeRacePlayers(raceID)
	local race = self:getRaceByID(raceID)
	if not race then
		return
	end

	for _, player in ipairs(race.players) do
		player.frozen = true
		if player.vehicle then
			toggleControl(player, "enter_exit", false)
			player.vehicle.frozen = true
		end
	end
end

function raceManager:unfreezeRacePlayers(raceID)
	local race = self:getRaceByID(raceID)
	if not race then
		return
	end

	for _, player in ipairs(race.players) do
		toggleControl(player, "enter_exit", true)
		player.frozen = false
		if player.vehicle then
			player.vehicle.frozen = false
		end
	end
end

function raceManager:announceWinnners(raceID)
	local race = self:getRaceByID(raceID)
	if not race then
		return
	end
	if not race.winners then
		return
	end

	local firstPlace = race.winners[1] and race.winners[1].playerName or nil
	local secondPlace = race.winners[2] and race.winners[2].playerName or nil
	local thirdPlace = race.winners[3] and race.winners[3].playerName or nil

	local text = ""

	text = firstPlace and (text .. "#FFFF00Первое место: " .. tostring(firstPlace)) or text
	text = text .. "\n"
	text = secondPlace and (text .. "#F0F0F0Второе место: " .. tostring(secondPlace)) or text
	text = text .. "\n"
	text = thirdPlace and (text .. "#CD7F32Третье место: " .. tostring(thirdPlace)) or text
	text = text .. "\n\n"

	-- объявляем победителям
	for place, winner in ipairs(race.winners) do
		if race.creator then
			if winner.player == race.creator then
				race.creatorInformed = true
			end
		end

		exports["tws-message-manager"]:showMessage(winner.player, "Гонка завершена", text .. "#00FF00Ваше место в гонке: #" .. place, "race")
	end

	-- объявляем тем, кто не успел финишировать
	for _, player in ipairs(race.players) do
		if not player:getData("tws-race.finished") then
			if not race.creatorInformed and race.creator then
				if player == race.creator then
					race.creatorInformed = true
				end
			end

			exports["tws-message-manager"]:showMessage(player, "Гонка завершена", text .. "#FFFFFFВы не успели финишировать.", "race")
		end
	end


	if not race.creatorInformed then
		if not race.creator then
			return
		end

		exports["tws-message-manager"]:showMessage(race.creator, "Гонка завершена", text, "race")
	end
end

--exports["tws-message-manager"]:showMessage("all", "Гонка завершена", "#FFFF00Первое место: AboriginalSalamander21\n#F0F0F0Второе место: UnevenEyebrows34\n#CD7F32Третье место: SuddenJupiter93\n\n#FFFFFFВы не успели финишировать.", "race", false, false)

-- выкидываем игроков из гонок при выходе с сервера
function playerQuit()
	local player = source

	local raceID = player:getData("raceID")
	if raceID then
		raceManager:removePlayerFromRace(player, raceID)
	end
end
addEventHandler("onPlayerQuit", root, playerQuit)

-- чистим дату у игроков при остановке ресурса
addEventHandler("onResourceStop", root,
	function(resourceStopped)
		if resourceStopped == getThisResource() then
			for _, player in ipairs(getElementsByType("player")) do
				player:setData("raceID", false)
				player:setData("creator_raceID", false)
			end
		end
	end
)

-- получаем гонку из едитора
addEventHandler("tws-race.onCreatorCreateRace", resourceRoot,
	function(checkpoints)
		local settings = {}

		settings.creator = client
		settings.creatorAccount = client.account:getName()
		settings.checkpoints = checkpoints
		settings.countdownEnabled = true
		settings.countdownFreeze = true
		settings.players = {client}
		settings.announcingWinnersEnabled = true
		settings.isCreatedByEditor = true
		settings.leavingVehicleAllowed = false
		settings.changingVehicleAllowed = false


		raceManager:createRace(settings)
	end
)
 
-- добавляем игроков из едитора
addEventHandler("tws-race.onClientInviteResponse", resourceRoot,
	function(raceID, response)
		local race = raceManager:getRaceByID(raceID)
		if not race then
			return
		end

		if not client then
			return
		end

		if race.state ~= "waiting" then
			exports["tws-message-manager"]:showMessage(client, "Гонка", "Гонка уже началась!", "error", 3000, true)
			return
		end

		if response == "yes" then
			local isAdded = raceManager:addPlayerToRace(client, race.id)
			if isAdded then
				exports["tws-message-manager"]:showMessage(client, "Менеджер создания гонок", "Вы были допущены к гонке!", "plus", 5000, true)
				if race.creator then
					exports["tws-message-manager"]:showMessage(race.creator, "Менеджер создания гонок", "Игрок " .. tostring(client.name) .. " согласился принять участие в гонке!", "plus", 4000, true)
				end
			end
		elseif response == "no" then
			if race.creator then
				exports["tws-message-manager"]:showMessage(race.creator, "Менеджер создания гонок", "Игрок " .. tostring(client.name) .. " отказался принять участие в гонке!", "error", 4000, true)
			end
		end

	end
)


function addOrRemovePlayer(playerID)
	if not client then
		return
	end

	local player = exports["tws-main"]:getPlayerByID(playerID)
	if not player then
		exports["tws-message-manager"]:showMessage(client, "Менеджер создания гонок", "Игрока с ID " .. playerID .. " не существует!", "error", 5000, true)
		return
	end

	local race = raceManager:getRaceByCreatorAccount(client.account:getName())
	if not race then
		return
	end

	if eventName == "tws-race.onCreatorAddPlayer" then
		-- если организатор приглашает сам себя
		if player == client then
			local result, reason = raceManager:addPlayerToRace(player, race.id)
			if result == true then
				exports["tws-message-manager"]:showMessage(client, "Менеджер создания гонок", "Вы допустили себя до своей гонки!", "plus", 5000, true)
			elseif reason == "already in race" then
				if race.id == player:getData("raceID") then
					exports["tws-message-manager"]:showMessage(client, "Менеджер создания гонок", "Вы уже допущены до своей гонки!", "info", 5000, true)
				else
					exports["tws-message-manager"]:showMessage(client, "Менеджер создания гонок", "Вы уже допущены к какой-то другой гонке!", "error", 5000, true)
				end
			end
		else
			if player:getData("raceID") then
				if race.id == player:getData("raceID") then
					exports["tws-message-manager"]:showMessage(client, "Менеджер создания гонок", "Игрок " .. player:getName() .. " уже допущен к вашей гонке!", "info", 5000, true)
				else
					exports["tws-message-manager"]:showMessage(client, "Менеджер создания гонок", "Игрок " .. player:getName() .. " уже допущен к какой-то другой гонке!", "error", 5000, true)
				end
			else
				-- кидаем инвайт игроку
				exports["tws-message-manager"]:showMessage(client, "Менеджер создания гонок", "Вы пригласили игрока " .. player.name .. " в вашу гонку!", "info", 4000, true)
				triggerClientEvent(player, "tws-race.onRaceInvite", resourceRoot, race.id, client.name)
			end
		end
	else
		local result, shit = raceManager:removePlayerFromRace(player, race.id, true)
		if result == true then
			if player == client then
				exports["tws-message-manager"]:showMessage(client, "Менеджер создания гонок", "Вы исключили себя из своей гонки!", "minus", 5000, true)
			else
				exports["tws-message-manager"]:showMessage(client, "Менеджер создания гонок", "Игрок " .. player:getName() .. " был исключен из вашей гонки!", "minus", 5000, true)
				exports["tws-message-manager"]:showMessage(player, "Менеджер создания гонок", "Организатор " .. client:getName() .. " исключил вас из своей гонки!", "minus", 7000, true)
			end
		end
	end
end
addEventHandler("tws-race.onCreatorAddPlayer", resourceRoot, addOrRemovePlayer)
addEventHandler("tws-race.onCreatorRemovePlayer", resourceRoot, addOrRemovePlayer)

-- стартовая и финишная линия
addEventHandler("tws-race.onCreatorDrawnLine", resourceRoot,
	function(whatLine, line)
		local creatorAccount = client.account:getName()
		local race = raceManager:getRaceByCreatorAccount(creatorAccount)
		if race then
			if whatLine == "start" then
				race.startLine = line
			elseif whatLine == "finish" then
				race.finishLine = line
			end

			for _, player in ipairs(race.players) do
				triggerClientEvent(player, "tws-race.onCreatorDrawnLine", resourceRoot, whatLine, line)
			end
			triggerClientEvent(client, "tws-race.onCreatorDrawnLine", resourceRoot, whatLine, line)
		else
			outputChatBox("Ошибка #" .. debug.getinfo(1).currentline .. " " .. debug.getinfo(1).source, client, 255, 100, 100)
		end
	end
)

-- запускаем гонку (editor)
addEventHandler("tws-race.onCreatorAsksForRaceStarting", resourceRoot,
	function()
		local race = raceManager:getRaceByCreatorAccount(client.account:getName())

		if not race then
			exports["tws-message-manager"]:showMessage(client, "Менеджер создания гонок", "Ошибка при старте гонки #" .. debug.getinfo(1).currentline .. " " .. debug.getinfo(1).source, "error", 5000, true)
			triggerClientEvent(client, "onServerResponseForRaceStarting", resourceRoot, false)
			return
		end

		raceManager:startRace(race.id)

		triggerClientEvent(client, "tws-race.onServerResponseForRaceStarting", resourceRoot, true)
	end
)


-- отменяем гонку
addEventHandler("tws-race.onCreatorAbandonRace", resourceRoot,
	function()
		local race = raceManager:getRaceByCreatorAccount(client.account:getName())
		if not race then
			return
		end

		raceManager:abandonRace(race.id, "creator")
	end
)

-- делаем блип
addEventHandler("tws-race.onCreatorToggleBlip", resourceRoot,
	function()
		local race = raceManager:getRaceByCreatorAccount(client.account:getName())
		if not race then
			return
		end

		raceManager:toggleBlip(race.id)
	end	
)

-- делаем таймер для удаления гонки при выходе создателя
local function playerLogout(account)
	local creatorAccount = account:getName()
	local race = raceManager:getRaceByCreatorAccount(creatorAccount)
	if race then
		if race.state ~= "waiting" then
			return
		end

		race.creator = nil

		for _, player in ipairs(race.players) do
			exports["tws-message-manager"]:showMessage(player, "Гонка", "Организатор гонки " .. tostring(getPlayerName(source)) .. " покинул сервер!\n\nГонка закончится через 10 минут, если организатор не переподключится.", "race", 15000, true)
		end

		race.timer = setTimer(
			function()
				race.timer = nil
				raceManager:abandonRace(race.id, "timer")
			end, 1000 * 60 * 10, 1
		)
	end
end
addEventHandler("onPlayerLogout", root, playerLogout)

-- восстанавливаем права создателя при логине
local function playerLogin(_, account)
	local race = raceManager:getRaceByCreatorAccount(account:getName())
	if race then
		if race.state ~= "waiting" then
			return
		end

		race.creator = account:getPlayer()
		race.creator:setData("creator_raceID", race.id)

		if race.timer and isTimer(race.timer) then
			killTimer(race.timer)
		end

		for _, player in ipairs(race.players) do
			exports["tws-message-manager"]:showMessage(player, "Гонка", "Организатор гонки " .. tostring(getPlayerName(race.creator)) .. " (" .. exports["tws-main"]:getPlayerID(race.creator) .. ") вернулся на сервер!", "race", 5000, true)
		end

		exports["tws-message-manager"]:showMessage(race.creator, "Менеджер создания гонок", "Ваши права организатора гонки были восстановлены.", "race", 10000, true)

		raceManager:addPlayerToRace(race.creator, race.id)
		triggerClientEvent(race.creator, "tws-race.onCreatorReconnect", resourceRoot, race)
	end
end
addEventHandler("onPlayerLogin", root, playerLogin)

addEventHandler("tws-race.onClientFinished", resourceRoot,
	function(raceID)
		local race = raceManager:getRaceByID(raceID)
		if not race or not client then
			return
		end

		local winner = {
			player = client,
			playerName = client:getName()
		}

		client:setData("tws-race.finished", true)

		table.insert(race.winners, winner)

		if #race.winners >= race.maxPlayersCount then
			if race.announcingWinnersEnabled and race.endTimer then
				if isTimer(race.endTimer) then
					killTimer(race.endTimer)
				end
				raceManager:announceWinnners(race.id)
			end
			raceManager:endRace(race.id)
		end

		if race.state == "running" then
			race.state = "finishing"

			-- если гонка сделана в едиторе
			if race.announcingWinnersEnabled then
				-- оповещаем игроков, что гонка завершена
				for _, player in ipairs(race.players) do
					if player ~= client then
						exports["tws-message-manager"]:showMessage(player, "Гонка", "Победитель гонки определен! Гонка будет завершена через " .. tostring(race.announcingTimeToWait and race.announcingTimeToWait/1000 or nil) .. " секунд или в тот момент, когда финишируют все участники гонки." , "race", 10000, true)
					end
				end

				-- завершаем гонку и объявляем победителей спустя announcingTimeToWait
				race.endTimer = setTimer(
					function()
						race.endTimer = nil

						raceManager:announceWinnners(race.id)

						raceManager:endRace(race.id)
					end, race.announcingTimeToWait, 1
				)
			end
		end
	end
)

addEventHandler("tws-race.onClientDisqualified", resourceRoot,
	function()
		if not client then
			return
		end
		local raceID = client:getData("raceID")
		if not raceID then
			return
		end
		local race = raceManager:getRaceByID(raceID)
		if not race then
			return
		end

		raceManager:removePlayerFromRace(client, raceID)
		for _, player in ipairs(race.players) do
			exports["tws-message-manager"]:showMessage(player, "Гонка", "Игрок " .. client:getName() .. " выбыл из гонки!", "race", 4000, true)
		end
	end
)