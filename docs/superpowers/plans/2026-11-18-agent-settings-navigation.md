# Agent settings navigation implementation plan

**Goal:** Make agent setup readable and usable on the Nexus 7 touch screen.

**Approach:** Keep the existing `flo-agent-config` interface and security handling. Split the settings panel into Remote and Local views, with Remote selected first. Keep host, user, agent choice, key setup, and test visible in Remote; place connection tuning and command overrides in an expandable Advanced section. Show Crush installation, provider, model, and API key only in Local. Preserve unsaved edits while switching views, and keep Save accessible in both.

**Files:** `shell/agents/AgentSettings.qml` for navigation and conditional sections; `shell/I18n.qml` for Italian and English labels; `docs/AGENT-PR-INTEGRATION.md` for the updated user flow.

**Checks:** Run `make check`; inspect the QML on the tablet, including both views, advanced controls, keyboard, and save/test actions. Confirm the existing PIN, touch, and session remain usable before claiming native completion.
