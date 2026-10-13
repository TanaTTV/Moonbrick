--!strict
-- Pure pixel math. The viewport is already device-safe; insets are the remaining CoreGui margins.
local HUDLayout = {}
export type Viewport = { width: number, height: number }
export type Insets = { left: number, top: number, right: number, bottom: number }
export type Layout = { x: number, y: number, width: number, height: number, scale: number }

function HUDLayout.layoutFor(viewport: Viewport, insets: Insets, noticeVisible: boolean?): Layout
	local safeWidth = math.max(0, viewport.width - insets.left - insets.right)
	local safeHeight = math.max(0, viewport.height - insets.top - insets.bottom)
	local height = if noticeVisible then 138 else 104
	-- Keep the lower controls clear even in phone landscape. Only the upper centre holds UI.
	local controls = if viewport.height < 420 then 120 else 160
	local scale = math.max(0, math.min(1.25, (safeWidth - 24) / 360, (safeHeight - 24 - controls) / height))
	return {
		x = insets.left + safeWidth / 2,
		y = insets.top + 12,
		width = 360,
		height = height,
		scale = scale,
	}
end

return HUDLayout
