import GotoSwift

print("=== Testing #gotoScope ===")

#gotoScope {
    line(10)
    var count = 0
    print("[Line 10] Starting counter with count = \(count)")

    line(20)
    count += 1
    print("[Line 20] Count is now: \(count)")
    if count < 3 {
        print("[Line 20] Jumping back to 20...")
        goto(20)
    }

    line(30)
    print("[Line 30] Calling subroutine at 100 via gosub(100)...")
    gosub(100)

    line(35)
    print("[Line 35] Successfully returned from subroutine!")

    line(40)
    print("[Line 40] Reached end of main scope.")
    end()

    line(100)
    print("[Line 100] Hello from subroutine!")
    returnLine()
}

print("\n=== Testing #basic ===")

#basic("""
10 LET X = 1
20 PRINT "BASIC COUNT: "; X
30 LET X = X + 1
40 IF X <= 3 THEN GOTO 20
50 GOSUB 100
60 PRINT "BASIC PROGRAM FINISHED"
70 END
100 PRINT "HELLO FROM BASIC SUBROUTINE!"
110 RETURN
""")

print("\n=== Testing #basic FOR ... NEXT Loops ===")

#basic("""
10 PRINT "Counting up with FOR I = 1 TO 3:"
20 FOR I = 1 TO 3
30 PRINT "  -> I = "; I
40 NEXT I
50 PRINT "Counting down with STEP -2:"
60 FOR J = 5 TO 1 STEP -2
70 PRINT "  -> J = "; J
80 NEXT J
90 PRINT "Nested FOR loops:"
100 FOR A = 1 TO 2
110 FOR B = 1 TO 2
120 PRINT "  -> A="; A; " B="; B
130 NEXT B
140 NEXT A
150 PRINT "ALL FOR LOOPS COMPLETED!"
160 END
""")

