// The names the hub screen uses, spelled here and nowhere else in hooks/ (tests/test_names.sh holds it to that). The twins of
// the constants at the top of bin/hh-lib.sh. The atoms' plugin (hooks/hub.tsx) and types/index.d.ts spell it as a literal: the
// engine reads both from the source.
export const PLUGIN = 'hivehouse' as const // the plugin's name, .claude-plugin/plugin.json: the atoms' namespace and `/<plugin>:hub`
export const PREFIX = 'hivehouse' // what a message from bin/ begins with: "<prefix>: ..."
export const HUB_DIR = '.hivehouse-hub' // the hub's folder, under its work folder
export const PANE = 'hivehouse-hub' // the hub screen's pane
