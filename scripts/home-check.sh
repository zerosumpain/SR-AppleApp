#!/usr/bin/env bash
# Build and test Home's pure Swift on Linux, in Docker.
#
#   scripts/home-check.sh
#
# Like `offline-check.sh`, for Home and msg family: the briefing's ranking
# (`Home/HomeBriefing.swift`), msg family's tools
# (`Family/FamilyMessageTools.swift`) and its landing's suggestions
# (`Family/FamilyChatSuggestions.swift`) are Foundation-only by design, so they
# are compiled here as a throwaway SwiftPM module NAMED `SRAppleApp` (the
# tests' `@testable import SRAppleApp` is untouched) with their test files
# (`HomeBriefingTests`, `FamilyMessageToolsTests`, `FamilyChatSuggestionsTests`)
# as its test target, in the swift:6.0-jammy image in Swift 5 language mode,
# as the app is. Every other file under Home/ is put through `swiftc -parse`:
# no imports resolved, no types checked, but the unbalanced brace is caught
# before CI.
#
# Exits non-zero on any failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${HOME_CHECK_IMAGE:-swift:6.0-jammy}"
BASE="${HOME_CHECK_TMP:-${TMPDIR:-/tmp}}"
APP="$ROOT/ios/SRAppleApp"
HOMEDIR="$APP/Home"
PURE=(Home/HomeBriefing.swift Family/FamilyMessageTools.swift Family/FamilyChatSuggestions.swift More/HubUsage.swift Home/HomeSizing.swift Family/FamilyMessagesWidgetModel.swift Games/GamesShelf.swift Games/Physics/LanderLogic.swift Games/Physics/CarRaceLogic.swift Games/Physics/PhysicsScores.swift Family/FamilyNowWidgetModel.swift Trips/TripsWidgetModel.swift Games/GamesWidgetModel.swift Health/HealthWidgetModel.swift Games/Physics/CarRaceSplitLogic.swift Games/ChessMarble/ChessMarbleConfetti.swift Games/ChessMarble/ChessRecords.swift Games/ChessMarble/MarbleRaceRecords.swift Games/GamesPagePlan.swift Games/Hometowns/HometownsLogic.swift Games/Hometowns/Sheets/HometownsProgress.swift Games/LiarsDiceOdds.swift Games/Manhunt/ManhuntPlayKit.swift Games/PartyRoomBests.swift Games/PassThePlateTally.swift Games/QuickRoomLogic.swift Games/TableGameRecords.swift Games/WordRooms/WordRoomBests.swift Games/Physics/MiniGolf/MiniGolfCourse.swift Games/Physics/MiniGolf/MiniGolfGeometry.swift Games/Physics/MiniGolf/MiniGolfHole.swift Games/Physics/MiniGolf/MiniGolfPhysics.swift Games/Physics/MiniGolf/MiniGolfRound.swift Games/Physics/Orbit/OrbitEffects.swift Games/Physics/Orbit/OrbitLevelKit.swift Games/Physics/Orbit/OrbitLevels.swift Games/Physics/Orbit/OrbitPhysics.swift Games/Physics/Orbit/OrbitProgress.swift Games/Physics/Orbit/OrbitRun.swift Games/Physics/Orbit/OrbitVector.swift Games/Physics/Orbit/OrbitWorld.swift Games/Physics/Pinball/PinballDotMatrix.swift Games/Physics/Pinball/PinballMachine.swift Games/Physics/Pinball/PinballPhysics.swift Games/Physics/Pinball/PinballRules.swift Games/Physics/Pinball/PinballScores.swift Games/Physics/Pinball/PinballSparks.swift Games/Physics/Pinball/PinballTable.swift Games/Physics/Pinball/PinballVector.swift Games/Physics/TiltMaze/TiltMazeAutopilot.swift Games/Physics/TiltMaze/TiltMazeBook.swift Games/Physics/TiltMaze/TiltMazeCatalogue.swift Games/Physics/TiltMaze/TiltMazeFormat.swift Games/Physics/TiltMaze/TiltMazeGenerator.swift Games/Physics/TiltMaze/TiltMazeLevel.swift Games/Physics/TiltMaze/TiltMazePhysics.swift Games/Puzzles/Merge2048/Merge2048Logic.swift Games/Puzzles/Merge2048/Merge2048Store.swift Games/Puzzles/Minesweeper/MinesweeperEffects.swift Games/Puzzles/Minesweeper/MinesweeperLogic.swift Games/Puzzles/Minesweeper/MinesweeperRecords.swift Games/Puzzles/Minesweeper/MinesweeperSolver.swift Games/Puzzles/Minesweeper/MinesweeperViewport.swift Games/Puzzles/Snake/SnakeLogic.swift Games/Puzzles/Snake/SnakeMazes.swift Games/Puzzles/Snake/SnakePath.swift Games/Puzzles/Snake/SnakeRecords.swift Games/Puzzles/Solitaire/SolitaireLayout.swift Games/Puzzles/Solitaire/SolitaireRules.swift Games/Puzzles/Solitaire/SolitaireSession.swift Games/Puzzles/Solitaire/SolitaireSolver.swift Games/Physics/CarPro/CarProLogic.swift Games/Physics/CarPro/CarProTyreLogic.swift Games/Physics/CarPro/CarProCarLogic.swift Games/Physics/CarPro/CarProPhysicsLogic.swift Games/Physics/CarPro/CarProTrackLogic.swift Games/Physics/CarPro/CarProCircuitsLogic.swift Games/Physics/CarPro/CarProLineLogic.swift Games/Physics/CarPro/CarProAILogic.swift Games/Physics/CarPro/CarProSessionLogic.swift Games/Physics/CarPro/CarProCareerLogic.swift Games/Physics/CarPro/CarProEffectsLogic.swift Games/Physics/CarPro/CarProPresentLogic.swift Games/Physics/CarPro/CarProSceneryLogic.swift)
TESTS=(HomeBriefingTests.swift FamilyMessageToolsTests.swift FamilyChatSuggestionsTests.swift HubUsageTests.swift HomeSizingTests.swift FamilyMessagesWidgetTests.swift GamesShelfTests.swift LanderLogicTests.swift CarRaceLogicTests.swift PhysicsScoresTests.swift FamilyNowWidgetTests.swift TripsWidgetTests.swift GamesWidgetTests.swift HealthWidgetTests.swift CarRaceSplitTests.swift ChessMarbleRecordsTests.swift GamesPagePlanTests.swift HometownsProgressTests.swift LiarsDiceOddsTests.swift ManhuntPlayKitTests.swift Merge2048LogicTests.swift MinesweeperLogicTests.swift MiniGolfCourseTests.swift MiniGolfPhysicsTests.swift MiniGolfRoundTests.swift OrbitTests.swift PartyRoomBestsTests.swift PassThePlateTallyTests.swift PinballTests.swift QuickRoomLogicTests.swift SnakeBoardTests.swift SnakeLogicTests.swift SolitaireSolverTests.swift SolitaireTests.swift TableGameRecordsTests.swift TiltMazeFormatTests.swift TiltMazeLevelTests.swift TiltMazePhysicsTests.swift WordRoomBestsTests.swift CarProPhysicsTests.swift CarProTrackTests.swift CarProCareerTests.swift CarProPresentationTests.swift)

command -v docker >/dev/null || { echo "home-check: docker is not installed" >&2; exit 2; }
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE" >/dev/null

mkdir -p "$BASE"
WORK="$(mktemp -d "$BASE/home-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Sources/SRAppleApp" "$WORK/Tests/SRAppleAppTests" "$WORK/parse"

for name in "${PURE[@]}"; do
  file="$APP/$name"
  imports="$({ grep -E '^[[:space:]]*import[[:space:]]' "$file" || true; } | awk '{print $NF}' | sort -u | tr '\n' ' ' | sed 's/ $//')"
  if [ "$imports" != "Foundation" ]; then
    echo "home-check: $name must import only Foundation (it imports: ${imports:-nothing})" >&2
    exit 1
  fi
  cp "$file" "$WORK/Sources/SRAppleApp/"
done
for file in "$HOMEDIR"/*.swift; do
  case " ${PURE[*]} " in *" Home/$(basename "$file") "*) continue ;; esac
  cp "$file" "$WORK/parse/"
done
for name in "${TESTS[@]}"; do cp "$ROOT/ios/SRAppleAppTests/$name" "$WORK/Tests/SRAppleAppTests/"; done

cat > "$WORK/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HomeCheck",
    products: [.library(name: "SRAppleApp", targets: ["SRAppleApp"])],
    targets: [
        .target(name: "SRAppleApp", path: "Sources/SRAppleApp"),
        .testTarget(name: "SRAppleAppTests", dependencies: ["SRAppleApp"], path: "Tests/SRAppleAppTests"),
    ],
    swiftLanguageVersions: [.v5]
)
SWIFT

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp/home \
  -v "$WORK:/pkg" -w /pkg \
  "$IMAGE" bash -c '
    set -uo pipefail
    mkdir -p "$HOME"
    status=0
    for f in ./parse/*.swift; do
      out=$(swiftc -parse "$f" 2>&1 | grep -v "warning: libc not found")
      if [ -n "$out" ]; then echo "--- parse: ${f#./parse/}"; echo "$out"; status=1; fi
    done
    [ "$status" = 0 ] && echo "home-check: parse clean" || echo "home-check: PARSE FAILED"
    swift build --build-tests 2>&1 | grep -v "^\[" ; build=${PIPESTATUS[0]}
    if [ "$build" != 0 ]; then echo "home-check: BUILD FAILED"; exit 1; fi
    swift test --skip-build 2>&1; test=$?
    if [ "$test" != 0 ]; then echo "home-check: TESTS FAILED"; exit 1; fi
    [ "$status" = 0 ] || exit 1
    echo "home-check: OK"
  '
