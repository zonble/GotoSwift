10 REM ======================================
20 REM   VINTAGE BASIC CHRISTMAS TREE DEMO
30 REM   GOTOSWIFT (1983 - 2026)
40 REM ======================================
50 LET H = 8
60 FOR I = 1 TO H
70   FOR S = 1 TO H - I
80     ? " ";
90   NEXT S
100  FOR A = 1 TO 2 * I - 1
110    ? "*";
120  NEXT A
130  ? ""
140 NEXT I
150 REM === TREE TRUNK ===
160 FOR T = 1 TO 2
170   FOR S = 1 TO H - 1
180     ? " ";
190   NEXT S
200   ? "|"
210 NEXT T
220 ? "  MERRY CHRISTMAS FROM RETRO BASIC! 🎄"
230 END
