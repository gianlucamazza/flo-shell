import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services

// flo-shell greeter for greetd: `quickshell -p greeter/`.
//
// A separate, much smaller configuration than the shell. Device, Theme,
// I18n, components/, lock/ and services/ are symlinks into ../shell, so the
// pad, the keyboard and the visual tokens are the very same files; of the
// services only Clock and Battery are ever instantiated here.
//
// Environment:
//   FLO_GREETER_USER          user selected at start (default: the first)
//   FLO_GREETER_USERS         comma-separated list instead of /etc/passwd
//   FLO_GREETER_SESSION       session command (default: flo-session)
//   FLO_GREETER_SESSIONS      session files offered, comma-separated basenames
//                             without .desktop, "*" for all (default: flo-shell)
//   FLO_GREETER_SESSIONS_DIR  where to look for *.desktop sessions
//   FLO_AUTH=dry              fake authentication and launch (development)
ShellRoot {
    id: root

    Greeter {
        id: greeter
    }

    // For tests: `quickshell ipc -p greeter call flo state`.
    IpcHandler {
        target: "flo"

        function state(): string {
            return JSON.stringify({
                users: greeter.users,
                user: greeter.user,
                sessions: greeter.sessions.map(s => s.name),
                session: greeter.sessionCommand,
                backend: greeter.backend,
                status: greeter.status,
                launched: greeter.launched,
                landscape: Device.landscape,
                lang: I18n.lang
            });
        }
        function user(name: string): void { greeter.selectUser(name); }
        function session(index: int): void { greeter.sessionIndex = index; }
        // Development only, inert without FLO_DEV_INPUT=1.
        function authInput(text: string): void { greeter.devType(text === "ENTER" ? "\n" : text); }
    }
}
