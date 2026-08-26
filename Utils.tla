------------------------ MODULE Utils ------------------------
EXTENDS Sequences, Naturals, FiniteSets

RECURSIVE SetToSeq(_)
SetToSeq(a) ==
    IF a = {} THEN <<>>
    ELSE 
        LET v == CHOOSE x \in a : TRUE 
        IN Append(SetToSeq(a \ {v}), v)

Max(a, b) == IF a < b THEN b ELSE a

MapSeq(seq, op(_)) ==
    IF Len(seq) = 0 THEN seq
    ELSE 
        LET f[n \in 1..Len(seq)] ==
            IF n = 1 THEN <<op(seq[1])>>
            ELSE Append(f[n - 1], op(seq[n]))
        IN f[Len(seq)]

FoldSeq(seq, op(_, _), base) ==
    IF Len(seq) = 0 THEN base 
    ELSE 
        LET f[n \in 1..Len(seq)] == 
            IF n = 1 THEN op(base, seq[n]) ELSE op(f[n-1], seq[n])
        IN f[Len(seq)]

SeqSum(s) == FoldSeq(s, +, 0)

MapSet(S, op(_)) == 
    LET f[s \in SUBSET S] ==
        IF s = {} THEN {}
        ELSE 
            LET x == CHOOSE v \in s : TRUE
            IN  {op(x)} \cup f[s \ {x}]
    IN  f[S]

FoldSet(set, op(_, _), base) ==
    LET f[s \in SUBSET set] == 
        IF s = {} THEN base 
        ELSE
            LET x == CHOOSE v \in s : TRUE 
            IN 
                op(f[s \ {x}], x)
    IN f[set]

==============================================================

