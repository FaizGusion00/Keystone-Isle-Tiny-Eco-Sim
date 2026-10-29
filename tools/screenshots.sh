#!/usr/bin/env bash
# Renders the README/store screenshot set at landscape (1280x720), phone portrait (720x1280) and
# desktop (1920x1080). Prints any script error or exit-time leak warning found in each log.
# Usage: tools/screenshots.sh [OUT_DIR]   (needs xvfb-run; GODOT env var points at the editor binary)
set -u
cd "$(dirname "$0")/.."
G=${GODOT:-/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64}
OUT=${1:-/workspace/keystone-shots}
mkdir -p "$OUT"
shot() { # w h name args...
	local w=$1 h=$2 n=$3; shift 3
	timeout 120 xvfb-run -a -s "-screen 0 ${w}x${h}x24" "$G" --audio-driver Dummy --resolution ${w}x${h} -- "$@" \
		--screenshot="$OUT/$n.png" > "/tmp/shot_$n.log" 2>&1
	grep -A3 "SCRIPT ERROR\|Parse Error\|leaked at exit\|still in use at exit" "/tmp/shot_$n.log"
	[ -f "$OUT/$n.png" ] && echo "ok  $n" || echo "FAIL $n"
}
FLOOD="--scenario=floodplain --farms-at=11,12;11,11;10,12 --until=FLOOD --no-results --zoom=1.8 --focus=event"
GAME="--scenario=expanding_village --farms=2 --ticks=160 --no-results --zoom=1.4 --focus=village"
CHAIN="--seed=7 --clear-rect=8,8,30,30 --farms=3 --ticks=700 --zoom=1.2 --focus=village --history=MUDDY_WATER"
DAM="--scenario=dam_decision --dams=1 --ticks=30 --no-results --zoom=2.2 --focus=dam --select=dam"
for o in "landscape 1280 720" "portrait 720 1280" "desktop 1920 1080"; do
	set -- $o; tag=$1; w=$2; h=$3
	shot $w $h ${tag}_01_main_menu --screen=menu
	shot $w $h ${tag}_02_campaign_select --screen=campaign
	shot $w $h ${tag}_03_gameplay_hud $GAME
	shot $w $h ${tag}_04_inspector $GAME --select=village
	shot $w $h ${tag}_05_why_chain $CHAIN
	shot $w $h ${tag}_06_rain_flood $FLOOD --history=FLOOD
	shot $w $h ${tag}_07_flooded_farm $FLOOD --select=event
	shot $w $h ${tag}_08_dam $DAM
	shot $w $h ${tag}_09_settings --screen=settings
	shot $w $h ${tag}_10_new_world --screen=new_world
	shot $w $h ${tag}_11_pause --screen=pause
	shot $w $h ${tag}_12_results --screen=results_won
	shot $w $h ${tag}_13_coach_marks --coach
	shot $w $h ${tag}_14_modes --screen=modes
	shot $w $h ${tag}_15_journal --screen=journal
	shot $w $h ${tag}_16_codex --screen=codex
	shot $w $h ${tag}_17_help --screen=help
	shot $w $h ${tag}_18_results_daily --screen=results_daily
done
