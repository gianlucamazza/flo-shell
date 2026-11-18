pragma Singleton

import QtQuick
import Quickshell

// User-visible strings and locale-aware formatting.
//
// The language follows the system locale (LC_ALL / LC_MESSAGES / LANG as
// read by Qt); FLO_LANG=it|en overrides it. Dates and times are formatted
// with the locale of the chosen language, so labels and dates always agree.
// Unknown languages fall back to English. Usage: I18n.t("key") or
// I18n.t("key", arg) where the string contains %1.
Singleton {
    id: root

    readonly property string lang: {
        const forced = (Quickshell.env("FLO_LANG") || "").toLowerCase();
        const sys = Qt.locale().uiLanguages.length > 0 ? Qt.locale().uiLanguages[0] : Qt.locale().name;
        const code = (forced !== "" ? forced : sys).substring(0, 2).toLowerCase();
        return tables[code] !== undefined ? code : "en";
    }
    readonly property var locale: Qt.locale(lang === "it" ? "it_IT" : Qt.locale().name.startsWith("en") ? Qt.locale().name : "en_GB")

    function t(key: string, arg: var): string {
        const s = tables[lang][key] ?? tables.en[key] ?? key;
        return arg === undefined ? s : s.replace("%1", arg);
    }

    function time(d: date): string {
        return locale.toString(d, "HH:mm");
    }
    function shortDate(d: date): string {
        return locale.toString(d, "ddd d MMM");
    }
    function longDate(d: date): string {
        return locale.toString(d, "dddd d MMMM");
    }

    readonly property var tables: ({
        it: {
            "power.title": "Alimentazione",
            "power.lock": "Blocca",
            "power.suspend": "Sospendi",
            "power.reboot": "Riavvia",
            "power.off": "Spegni",
            "power.confirm": "Conferma",
            "power.confirmHint": "Tocca di nuovo per confermare",
            "power.battery": "Batteria %1%",
            "power.charging": ", in carica",
            "common.cancel": "Annulla",
            "qs.notifications": "Notifiche",
            "qs.notificationsCount": "Notifiche (%1)",
            "qs.clearAll": "Cancella tutto",
            "qs.none": "Nessuna notifica",
            "qs.off": "Spento",
            "qs.on": "Acceso",
            "qs.connected": "Connesso",
            "qs.notConnected": "Non connesso",
            "qs.unavailable": "Non disponibile",
            "qs.rotate": "Ruota",
            "qs.portrait": "Verticale",
            "qs.landscape": "Orizzontale",
            "qs.power": "Alimentazione",
            "qs.chargingShort": " in carica",
            "launcher.search": "Cerca app",
            "launcher.empty": "Nessuna app trovata",
            "overview.title": "App aperte",
            "overview.empty": "Nessuna app aperta",
            "overview.closeAll": "Chiudi tutto",
            "overview.hint": "Tocca per aprire, trascina in alto per chiudere",
            "lock.enterPin": "Inserisci il PIN",
            "lock.enterPassword": "Inserisci la password",
            "lock.checking": "Verifica in corso…",
            "lock.wrong": "Codice errato",
            "lock.error": "Errore di autenticazione",
            "lock.tooMany": "Troppi tentativi",
            "lock.notifications.one": "1 notifica",
            "lock.notifications.many": "%1 notifiche",
            "lock.usePassword": "abc",
            "lock.usePin": "123",
            "lock.dryRun": "Prova: autenticazione finta",
            "greeter.starting": "Avvio della sessione…",
            "greeter.noGreetd": "greetd non disponibile",
            "greeter.noUsers": "Nessun utente trovato",
            "agents.settings": "Impostazioni agenti",
            "agents.host": "Host",
            "agents.user": "Utente",
            "agents.port": "Porta",
            "agents.transport": "Trasporto",
            "agents.mosh": "mosh",
            "agents.ssh": "ssh",
            "agents.tools": "Agenti",
            "agents.remote": "remoto",
            "agents.remoteCmd": "Comando remoto",
            "agents.default": "Agente predefinito",
            "agents.tmux": "tmux",
            "agents.tmuxPrefix": "Prefisso della sessione",
            "agents.save": "Salva",
            "agents.saving": "Salvataggio…",
            "agents.test": "Prova connessione",
            "agents.testing": "Verifica…",
            "agents.deviceKey": "Chiave del dispositivo",
            "agents.createKey": "Crea chiave",
            "agents.showKey": "Mostra chiave",
            "agents.copy": "Copia",
            "agents.working": "Un momento…",
            "agents.authorizedKeysHint": "Aggiungi questa riga a ~/.ssh/authorized_keys sull'host.",
            "agents.reachable": "Raggiungibile",
            "agents.unreachable": "Non raggiungibile",
            "agents.present": "presente",
            "agents.missing": "assente",
            "agents.hostKeyNew": "La chiave dell'host è stata accettata al primo utilizzo.",
            "agents.hostKeyChanged": "La chiave dell'host è cambiata. Impossibile continuare. Rimuovi la voce non più valida in known_hosts su questo dispositivo, poi riprova.",
            "agents.localCrush": "Agente locale (Crush)",
            "agents.install": "Installa",
            "agents.uninstall": "Disinstalla",
            "agents.installing": "Installazione…",
            "agents.uninstalling": "Disinstallazione…",
            "agents.installHint": "L'installazione scarica circa 28 MB.",
            "agents.provider": "Provider",
            "agents.baseUrl": "URL di base",
            "agents.model": "Modello",
            "agents.apiKey": "Chiave API",
            "agents.saveKey": "Salva chiave",
            "agents.removeKey": "Rimuovi chiave",
            "agents.keySet": "Chiave impostata ••••%1",
            "agents.keyUnset": "Chiave non impostata",
            "agents.crushVersion": "Versione %1"
        },
        en: {
            "power.title": "Power",
            "power.lock": "Lock",
            "power.suspend": "Suspend",
            "power.reboot": "Restart",
            "power.off": "Power off",
            "power.confirm": "Confirm",
            "power.confirmHint": "Tap again to confirm",
            "power.battery": "Battery %1%",
            "power.charging": ", charging",
            "common.cancel": "Cancel",
            "qs.notifications": "Notifications",
            "qs.notificationsCount": "Notifications (%1)",
            "qs.clearAll": "Clear all",
            "qs.none": "No notifications",
            "qs.off": "Off",
            "qs.on": "On",
            "qs.connected": "Connected",
            "qs.notConnected": "Not connected",
            "qs.unavailable": "Unavailable",
            "qs.rotate": "Rotate",
            "qs.portrait": "Portrait",
            "qs.landscape": "Landscape",
            "qs.power": "Power",
            "qs.chargingShort": " charging",
            "launcher.search": "Search apps",
            "launcher.empty": "No apps found",
            "overview.title": "Open apps",
            "overview.empty": "No open apps",
            "overview.closeAll": "Close all",
            "overview.hint": "Tap to open, drag up to close",
            "lock.enterPin": "Enter PIN",
            "lock.enterPassword": "Enter password",
            "lock.checking": "Checking…",
            "lock.wrong": "Wrong code",
            "lock.error": "Authentication error",
            "lock.tooMany": "Too many attempts",
            "lock.notifications.one": "1 notification",
            "lock.notifications.many": "%1 notifications",
            "lock.usePassword": "abc",
            "lock.usePin": "123",
            "lock.dryRun": "Test mode: fake authentication",
            "greeter.starting": "Starting session…",
            "greeter.noGreetd": "greetd is not available",
            "greeter.noUsers": "No users found",
            "agents.settings": "Agent settings",
            "agents.host": "Host",
            "agents.user": "User",
            "agents.port": "Port",
            "agents.transport": "Transport",
            "agents.mosh": "mosh",
            "agents.ssh": "ssh",
            "agents.tools": "Agents",
            "agents.remote": "remote",
            "agents.remoteCmd": "Remote command",
            "agents.default": "Default agent",
            "agents.tmux": "tmux",
            "agents.tmuxPrefix": "Session prefix",
            "agents.save": "Save",
            "agents.saving": "Saving…",
            "agents.test": "Test connection",
            "agents.testing": "Testing…",
            "agents.deviceKey": "Device key",
            "agents.createKey": "Create key",
            "agents.showKey": "Show key",
            "agents.copy": "Copy",
            "agents.working": "Working…",
            "agents.authorizedKeysHint": "Add this line to ~/.ssh/authorized_keys on the host.",
            "agents.hostKeyNew": "The host key was trusted on first use.",
            "agents.hostKeyChanged": "The host key has changed. Refusing to continue. Remove the stale known_hosts entry on this device, then test again.",
            "agents.reachable": "Reachable",
            "agents.unreachable": "Not reachable",
            "agents.present": "present",
            "agents.missing": "missing",
            "agents.localCrush": "Local agent (Crush)",
            "agents.install": "Install",
            "agents.uninstall": "Uninstall",
            "agents.installing": "Installing…",
            "agents.uninstalling": "Uninstalling…",
            "agents.installHint": "Install downloads about 28 MB.",
            "agents.provider": "Provider",
            "agents.baseUrl": "Base URL",
            "agents.model": "Model",
            "agents.apiKey": "API key",
            "agents.saveKey": "Save key",
            "agents.removeKey": "Remove key",
            "agents.keySet": "Key set ••••%1",
            "agents.keyUnset": "Key unset",
            "agents.crushVersion": "Version %1"
        }
    })
}
