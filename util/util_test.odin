package ravn_util

@(test)
_cp437_rune_char_table :: proc(t: ^testing.T) {
    for ch in 0..<max(u8) {
        testing.expectf(t, ch == rune_to_cp437(cp437_to_rune(ch)), "%v : %v", ch, cp437_to_rune(ch))
    }
}
