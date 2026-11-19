-- flo-shell on Nexus 7 2013. Hyprland >= 0.55; 0.54 uses hyprland.conf.
hl.monitor({ output = "DSI-1", mode = "preferred", position = "0x0", scale = 2 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QSG_RHI_BACKEND", "opengl")
hl.env("GDK_BACKEND", "wayland")
hl.env("GSK_RENDERER", "cairo")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("XCURSOR_SIZE", "24")
hl.env("LANG", "it_IT.UTF-8")
hl.env("XDG_DATA_DIRS", "/usr/share/flo-shell/xdg:/usr/local/share:/usr/share")

hl.config({
    general = { gaps_in = 0, gaps_out = 0, border_size = 0, layout = "monocle", allow_tearing = false },
    decoration = {
        rounding = 0, dim_inactive = false,
        blur = { enabled = false }, shadow = { enabled = false },
    },
    animations = { enabled = false },
    input = { kb_layout = "it", follow_mouse = 1, touchdevice = { output = "DSI-1" } },
    gestures = { workspace_swipe_touch = true, workspace_swipe_cancel_ratio = 0.3, workspace_swipe_create_new = true },
    cursor = { hide_on_touch = true, inactive_timeout = 3 },
    misc = {
        disable_hyprland_logo = true, disable_splash_rendering = true,
        force_default_wallpaper = 0, background_color = 0x0f1115,
        focus_on_activate = true, allow_session_lock_restore = true,
        key_press_enables_dpms = true, mouse_move_enables_dpms = false,
        disable_hyprland_guiutils_check = true, enable_anr_dialog = false,
    },
    xwayland = { enabled = false },
    ecosystem = { no_update_news = true, no_donation_nag = true },
})

hl.bind("XF86PowerOff", hl.dsp.exec_cmd("flo-shell msg powerKey"), { release = true, locked = true })
hl.bind("XF86PowerOff", hl.dsp.exec_cmd("flo-shell msg powerKeyLong"), { long_press = true, locked = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("flo-shell msg volume 5"), { repeating = true, locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("flo-shell msg volume -5"), { repeating = true, locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("flo-shell msg mute"), { locked = true })

hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE")
    hl.exec_cmd("systemctl --user start flo-shell-session.target")
    hl.exec_cmd("/usr/libexec/hyprpolkitagent")
    hl.exec_cmd("flo-shell run")
end)
