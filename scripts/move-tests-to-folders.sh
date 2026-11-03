#!/bin/zsh
# 1A3: move NoteCodeTests/*.swift (and NoteCode.storekit) into the folders that
# mirror NoteCode/. A test goes where the type it tests lives.
#
#   scripts/move-tests-to-folders.sh [--dry-run]
#
# Stops if a file at the top of NoteCodeTests/ has no row, or a row names a
# missing file. Nothing inside any file changes.

set -uo pipefail
cd ${0:A:h:h}
dry=0; [[ ${1:-} == --dry-run ]] && dry=1

typeset -A map
add() { local d=$1; shift; for f in "$@"; do [[ -n ${map[$f]:-} ]] && { print -u2 "named twice: $f"; exit 1 }; map[$f]=$d; done }

add App/ AppIconTests AppStoreReadinessTests CompactLayoutTests NoteShortcutTests NoteWindowControlTests ReviewPromptTests
add Debug/ DebugLaunchTests
add Code/ CodeBlockActionBarTests CodeBlockActionTests CodeBlockIdentityTests CodeBlockPageBreakTests CodeBlockPanelTests CodeBlockPositionTests CodeBlockRoomTests CodeDestinationTests CodeEditingFixesTests CodeFenceCostTests CodeFenceDisplayTests CodeIndentTests CodeKeysTests CodeLanguagesTests HighlightAlignmentTests LastCodeLanguageTests LineNumbersTests OutputBlockTests SyntaxHighlightingTests SyntaxThemeTests TokenEdgeTests
add Formula/ DisplayFormulaTests FormulaEditingTests FormulaLayoutTests FormulaValidityTests MathParserTests
add Ink/ DrawingCanvasTests DrawingCodecTests DrawingSaveSchedulerTests FingerDrawsPersistenceTests InkBlendTests InkContainerTests InkInsertTests InkObjectCommandTests InkPagesTests InkPaletteTests InkSelectionTests InkToolHandoverTests InkWidthStepTests PaperKitSelectionRemovalTests
add InOut/ NoteInterchangeTests NotePDFTests
add Library/ FolderAppearanceTests FolderBadgeRenderTests HomeSectionsTests ListDropHitTests NoteIconTests NoteListFirstRunTests NoteListTests NoteSearchTests NoteTemplatesTests NoteThumbnailTests RecentlyDeletedTests SidebarOnHomeTests
add Model/ FolderTests ModelFreezeTests NestedFolderTests NoteInfoTests NoteMemoryTests NoteTitleTests StorageTests
add NotePage/ CanvasGeometryTests EditorLeakTests EditorModeTests HotbarDockTests HotbarIconPixelTests HotbarLayoutTests KeyboardInsetTests NoteEditorTests NoteOutlineTests NotePageChromeTests PageLayoutTests PageMotionTests PageOverlayTests PageSettlingTests PageViewTests ReopenTests TextBarLayoutTests
add Settings/ AccentPaletteTests SettingsTests
add Pro/Ads/ AdTests
add Pro/Assistant/ AIEditorTests AIFeaturesTests AISystemModelTests
add Pro/Run/ CodeRunnerTests RunSessionTests RunWiringTests
add Pro/Store/ PaywallTests ProStatusTests TipJarTests
add Text/Core/ DocumentParserTests FenceVisibilityTests InlineMarksTests InlineParserTests ListTests MarkdownFormattingTests NestingInlineTests SpanSizeTests StyledLineTests TextColourTests TextRowTests TypingStyleTests
add Text/Editor/ CaretAnywhereTests CaretHeightTests DocumentStylerTests DocumentTextViewTests EditingBehaviorTests HeadingMarkerTests KeyboardAndMenuTests LinkTapTests MarkerDimmingTests MarkerEditingTests ReturnAndBackspaceTests RichClipboardTests RichPasteTests StylingPerformanceTests TextRegionSelectionTests TextRewritingPolicyTests TextSizeCostTests TextSizeTests CodeSelectionHighlightTests
add Text/Layout/ LineSpacingTests MarkdownLayoutTests ProseBlockTests
add TestSupport/ TestSupportTests TestWindow TopLevelSpans

moved=0
for f in NoteCodeTests/*.swift; do
  b=${f:t:r}
  [[ -n ${map[$b]:-} ]] || { print -u2 "no row for $f"; exit 1 }
done
for b in ${(k)map}; do
  src=NoteCodeTests/$b.swift
  [[ -f $src ]] || { print -u2 "missing: $src"; exit 1 }
  dst=NoteCodeTests/${map[$b]}$b.swift
  if (( dry )); then print "$src -> $dst"
  else mkdir -p ${dst:h} && git mv $src $dst || exit 1; fi
  (( moved++ ))
done
# 2S1's ProKeysTests already sits in Pro/; its subject, ProSettings, is in Pro/Store.
if (( dry )); then print "NoteCodeTests/Pro/ProKeysTests.swift -> NoteCodeTests/Pro/Store/ProKeysTests.swift"
else mkdir -p NoteCodeTests/Pro/Store && git mv NoteCodeTests/Pro/ProKeysTests.swift NoteCodeTests/Pro/Store/ProKeysTests.swift || exit 1; fi
(( moved++ ))
# The StoreKit configuration TipJarTests loads from the test bundle.
if (( dry )); then print "NoteCodeTests/NoteCode.storekit -> NoteCodeTests/Pro/Store/NoteCode.storekit"
else mkdir -p NoteCodeTests/Pro/Store && git mv NoteCodeTests/NoteCode.storekit NoteCodeTests/Pro/Store/NoteCode.storekit || exit 1; fi
(( moved++ ))
print "moved $moved"
