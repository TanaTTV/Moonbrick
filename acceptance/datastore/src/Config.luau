--!strict
return {
	-- Fill ONLY after the owner approves a NEW private disposable experience.
	-- [PLACE_ID] = UNIVERSE_ID (game.GameId). Empty means no DataStore acquisition.
	allowedPlaces = {} :: { [number]: number },
	-- suite | shutdown-arm | shutdown-verify | stale-arm | stale-verify | contender-a | contender-b | cleanup
	mode = "suite",
	-- Blank: suite generates one. Manual modes require the SAME explicit ID, 1..12 alphanumerics.
	runId = "",
}
