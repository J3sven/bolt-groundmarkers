local M = {}

function M.bind(state, bolt, tiles, colors)
  -- Scroll with CTRL to step color (and recolor current tile if standing on one)
  bolt.onscroll(function(event)
    if event:ctrl() then
      local forward = event:direction()
      colors.stepColor(state, bolt, forward)
      tiles.recolorCurrentTile(state, bolt)
    end
  end)

  -- Middle mouse actions
  bolt.onmousebutton(function(event)
    if event:button() ~= 3 then return end  -- middle

    if event:alt() then
      -- Alt + Middle: toggle marker at player
      tiles.toggleTileMarker(state, bolt)
    elseif event:ctrl() then
      -- Ctrl + Middle: cycle color, recolor tile if on one
      colors.cycleColor(state, bolt)
      tiles.recolorCurrentTile(state, bolt)
    end
  end)
end

return M
