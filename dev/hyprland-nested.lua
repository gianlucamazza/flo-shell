-- Minimal Hyprland configuration for running flo-shell in a nested,
-- headless instance (see dev/run-nested.sh). No autostart, no effects.
-- Needs a Hyprland build that reads Lua configuration.
hl.monitor({ output = "FLO", mode = "600x960@60", position = "0x0", scale = 1 })
hl.config({
    animations = { enabled = false },
    decoration = { rounding = 0, blur = { enabled = false }, shadow = { enabled = false } },
    general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
    misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
})
