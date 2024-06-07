// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

/// @dev https://icap.org.pk/files/per/students/exam/notices/log-table.pdf
bytes constant LOG_TABLE =
// | 10 | 0000 | 0043 | 0086 | 0128 | 0170 | 0212' | 0253' | 0294' | 0334' | 0374' |
 hex"0000" hex"002b" hex"0056" hex"0080" hex"00aa" hex"80d4" hex"80fd" hex"8126" hex"814e" hex"8176"
 // | 11 | 0414 | 0453 | 0492 | 0531 | 0569 | 0607' | 0645' | 0682' | 0719' | 0755' |
    hex"019e" hex"01c5" hex"01ec" hex"0213" hex"0239" hex"825f" hex"8285" hex"82aa" hex"82cf" hex"82f3";

bytes constant LOG_TABLE_SMALL =
// | 10 | 0 | 4 | 9 | 13 | 17 | 21 | 26 | 30 | 34 | 38 |
 hex"00" hex"04" hex"09" hex"0d" hex"11" hex"15" hex"1a" hex"1e" hex"22" hex"26"
// | 11 | 0 | 4 | 8 | 12 | 15 | 19 | 23 | 27 | 31 | 35 |
hex"00" hex"04" hex"08" hex"0c" hex"0f" hex"13" hex"17" hex"1b" hex"1f" hex"23";

bytes constant LOG_TABLE_SMALL_ALT =
// | 10 | 0 | 4 | 8 | 12 | 16 | 20 | 24 | 28 | 32 | 37 |
 hex"00" hex"04" hex"08" hex"0c" hex"10" hex"14" hex"18" hex"1c" hex"20" hex"25"
// | 11 | 0 | 4 | 7 | 11 | 15 | 19 | 22 | 26 | 30 | 33 |
 hex"00" hex"04" hex"07" hex"0b" hex"0f" hex"13" hex"16" hex"1a" hex"1e" hex"21";