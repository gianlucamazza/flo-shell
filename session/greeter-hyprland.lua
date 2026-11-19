-- greetd compositor, Hyprland >= 0.55. No cursor, including at startup.
hl.monitor({ output = "DSI-1", mode = "preferred", position = "0x0", scale = 2 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QSG_RHI_BACKEND", "opengl")
hl.env("LANG", "it_IT.UTF-8")
hl.config({
    general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
    decoration = { rounding = 0, blur = { enabled = false }, shadow = { enabled = false } },
    animations = { enabled = false },
    cursor = { invisible = true },
    input = { kb_layout = "it", touchdevice = { output = "DSI-1" } },
    misc = {
        disable_hyprland_logo = true, disable_splash_rendering = true,
        force_default_wallpaper = 0, background_color = 0x0f1115,
        key_press_enables_dpms = true, disable_hyprland_guiutils_check = true,
    },
    ecosystem = { no_update_news = true, no_donation_nag = true },
    xwayland = { enabled = false },
})
hl.on("hyprland.start", function()
    hl.exec_cmd([[sh -c 'flo-shell greeter; hyprctl dispatch "hl.dsp.exit()"']])
end)
