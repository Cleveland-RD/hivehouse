// The names the hub screen uses, spelled here and nowhere else in hooks/ (tests/test_names.sh holds it to that). The twins of
// the constants at the top of bin/hm-lib.sh. The atoms' plugin (hooks/hub.tsx) and types/index.d.ts spell it as a literal: the
// engine reads both from the source.
export const PLUGIN = 'hivemind' as const // the plugin's name, .claude-plugin/plugin.json: the atoms' namespace and `/<plugin>:hub`
export const PREFIX = 'hivemind' // what a message from bin/ begins with: "<prefix>: ..."
export const HUB_DIR = '.hivemind-hub' // the hub's folder, under its work folder
export const PANE = 'hivemind-hub' // the hub screen's pane
