# Mushaf line engine

The user's printed-Quran reference requires a rectangular body with natural
Hafs word spacing. This supersedes the earlier single-paragraph right-alignment
decision. Keep the bundled font, corpus text, verse markers and offline preview.

Use the bundled printed word boundaries for page mode. Shape each line as one
RTL unit with normal font spaces, then fit that entire unit to both paper edges.
Never justify whitespace, lay out separate spaced word boxes, or wrap a complete
page in one paragraph. Actual surah-ending lines remain naturally right-aligned;
a page's last line is fitted unless it is also a surah ending. Opening banners
and Bismillah remain separate blocks. For targets without printed metadata,
measure complete word-and-marker units and greedily allocate measured lines.

Keep line geometry independent of live verdicts, Tajweed colours and Hifz
visibility. Cursor anchors and mistake taps must use the same scaled line
geometry. Preserve all source words and tightly coupled verse markers. Fifteen
printed body lines on Page 3 must remain fifteen lines at phone widths.

Verify real-font glyph margins and transformed space advances, phone/tablet
captures, all 604 page boundaries, surah endings, all modes and scrolling.
Commit and push the change and build the separate offline Qari UI Preview APK.
