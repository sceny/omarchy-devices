#!/bin/bash
# The script checks of R3 (docs/internals/releasing.md), run by dev/regression
# inside the sandbox after `dev/rig up`, with the candidate tree as the working
# directory.
#
# Writes $SANDBOX_OUT/features.tsv: feature, rule, how, result, evidence.
# A measured row is pass or fail. A "look" row is judged by a person from the
# screenshot named in its evidence. A "not yet" row is one this script does not
# measure; it is never written as a pass. Exits 1 when a measured row fails.

set -u

OUT_DIR="${SANDBOX_OUT:?SANDBOX_OUT is set by dev/sandbox run}"
mkdir -p "$OUT_DIR"
TSV="$OUT_DIR/features.tsv"
printf 'feature\trule\thow\tresult\tevidence\n' > "$TSV"

# The sandbox brings the rig up with no owner, and a rig with no owner is found
# only by its id.
RIG_SELECT=$(dev/rig ps --json | jq -r '.rigs[0].id') || exit 1
[[ -n $RIG_SELECT && $RIG_SELECT != null ]] || { echo "no rig is up" >&2; exit 1; }
export RIG_SELECT

failed=0

row() {
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$TSV"
}

measured() {
    local feature="$1" rule="$2" how="$3" evidence="$4"
    shift 4
    if "$@" > "$OUT_DIR/$evidence" 2>&1; then
        row "$feature" "$rule" "$how" pass "$evidence"
    else
        row "$feature" "$rule" "$how" fail "$evidence"
        failed=1
    fi
}

look() {
    row "$1" "$2" "$3" look "$4"
}

not_yet() {
    row "$1" "$2" "$3" "not yet" "-"
}

in_rig() {
    dev/rig exec -- "$@"
}

shell_json() {
    local dir
    dir=$(in_rig printenv XDG_CONFIG_HOME) || return 1
    printf '%s/omarchy/shell.json\n' "$dir"
}

loaded_code() {
    in_rig dev/loaded-code .
}

settings_persist() {
    local sj before after toggled again
    sj=$(shell_json) || return 1
    before="$OUT_DIR/shell-before.json"
    in_rig cat "$sj" > "$before" 2>/dev/null || printf '{}' > "$before"

    dev/rig restart-shell || return 1
    after="$OUT_DIR/shell-after-restart.json"
    in_rig cat "$sj" > "$after" 2>/dev/null || printf '{}' > "$after"
    [[ $(sha256sum < "$before") == "$(sha256sum < "$after")" ]] ||
        { echo "shell.json changed across a restart with no change made"; return 1; }

    toggled=$(dev/rig ipc fold apps) || return 1
    echo "fold apps -> $toggled"
    sleep 1
    in_rig cat "$sj" > "$OUT_DIR/shell-folded.json" || return 1
    jq -e --argjson v "$(jq -c '.apps // false' <<<"$toggled")" \
        '[.. | objects | select(has("collapsed")) | .collapsed.apps // false] | any(. == $v)' \
        "$OUT_DIR/shell-folded.json" >/dev/null ||
        { echo "the fold was not written to shell.json"; return 1; }

    dev/rig restart-shell || return 1
    in_rig cat "$sj" > "$OUT_DIR/shell-after-second-restart.json" || return 1
    jq -e --argjson v "$(jq -c '.apps // false' <<<"$toggled")" \
        '[.. | objects | select(has("collapsed")) | .collapsed.apps // false] | any(. == $v)' \
        "$OUT_DIR/shell-after-second-restart.json" >/dev/null ||
        { echo "the fold did not survive the restart"; return 1; }
}

clip_check() {
    local id
    id=$(dev/rig ps --json | jq -r '.rigs[0].id') || return 1
    [[ -n $id && $id != null ]] || { echo "no rig id"; return 1; }
    dev/clip-check --rig "$id"
}

versions_recorded() {
    {
        in_rig quickshell --version || true
        in_rig pacman -Q qt6-base || true
    } > "$OUT_DIR/versions.txt" 2>&1
    grep -Eiq 'quickshell.*[0-9]+\.[0-9]+' "$OUT_DIR/versions.txt" &&
        grep -Eq '^qt6-base [0-9]' "$OUT_DIR/versions.txt"
}

header_shots() {
    dev/rig ipc fold apps >/dev/null || return 1
    sleep 1
    dev/rig screenshot "$OUT_DIR/headers-folded.png" || return 1
    dev/rig ipc fold apps >/dev/null || return 1
    sleep 1
    dev/rig screenshot "$OUT_DIR/headers-open.png" || return 1
}

cold_first_run() {
    dev/rig cold begin || return 1
    dev/rig ipc status || return 1
    loaded_code || return 1
    dev/rig ipc open >/dev/null || return 1
    sleep 1
    dev/rig screenshot "$OUT_DIR/cold-card.png" || return 1
}

measured "Panel answers over IPC" \
    "The panel answers over IPC after the rig comes up" \
    "dev/rig ipc status" "ipc-status.log" \
    dev/rig ipc status

measured "Loaded code" \
    "The running shell runs the plugin's files" \
    "dev/loaded-code" "loaded-code.log" \
    loaded_code

measured "Settings persist across a restart" \
    "What the user arranged is still there after a shell restart, and nothing is written until a change" \
    "shell.json read back before and after a restart; dev/rig ipc fold" "settings-persist.log" \
    settings_persist

measured "Clipboard" \
    "The clipboard leaves on the user's act only" \
    "dev/clip-check --rig ID" "clip-check.log" \
    clip_check

measured "Versions recorded" \
    "The run records the Quickshell and Qt versions it tested" \
    "quickshell --version, pacman -Q qt6-base" "versions.txt" \
    versions_recorded

if header_shots > "$OUT_DIR/headers.log" 2>&1; then
    look "Section headers" \
        "Every header is one height, folded or open" \
        "dev/rig ipc fold apps, dev/rig screenshot" "headers-folded.png, headers-open.png"
else
    row "Section headers" "Every header is one height, folded or open" \
        "dev/rig ipc fold apps, dev/rig screenshot" fail "headers.log"
    failed=1
fi

measured "Panel answers on a cold computer" \
    "The panel runs with none of the plugin's packages installed" \
    "dev/rig cold begin, dev/rig ipc status, dev/loaded-code" "cold.log" \
    cold_first_run

look "First-run card" \
    "The first-run card installs what is missing in one password, then goes on" \
    "dev/rig cold begin, dev/rig ipc open, dev/rig screenshot" "cold-card.png"

not_yet "Upgrade from the live tag" \
    "Old settings are kept, IPC answers and the code matches after the upgrade" \
    "needs the live tag's tree beside the candidate; dev/sandbox run takes one commit"
not_yet "Firewall rules across the upgrade" \
    "The firewall rules are unchanged by an upgrade" \
    "part of the upgrade; not automated"
not_yet "Two devices: profiles" \
    "A device's own changes go into its profile" \
    "needs a second device; the emulator is one phone"
not_yet "Media: seek" \
    "Nothing blinks on a seek" \
    "the emulator has no media player to seek"

exit "$failed"
