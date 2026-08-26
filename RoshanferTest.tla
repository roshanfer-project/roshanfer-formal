------------------------ MODULE RoshanferTest ------------------------
EXTENDS Integers

VARIABLES
    Pending,
    Granted,
    Done,
    Waiting,
    CreditRequestQueues,
    Cs,
    Ns,
    Downstream,
    Requested,
    Processing

vars == <<
        Pending, 
        Granted, 
        Done, 
        Waiting, 
        CreditRequestQueues, 
        Cs,
        Ns, 
        Downstream, 
        Requested, 
        Processing
    >>

Roshanfer == INSTANCE Roshanfer WITH 
    EndpointLimits <- <<
        <<1, 1>>,
        <<1, 1>>,
        <<1, 1>>,
        <<1, 1>>,
        <<1>>
    >>,
    GlobalLimits <- <<
        -1, -1, -1, 1, 1
    >>,
    ServerDownstreams <- <<
        <<
            <<{[service |-> 2, endpoint |-> 1], [service |-> 5, endpoint |-> 1]}>>,     \* Service 1 Endpoint 1
            <<{[service |-> 3, endpoint |-> 2]}>>                                       \* Service 1 Endpoint 2
        >>,
        <<
            <<{[service |-> 4, endpoint |-> 1]}, {[service |-> 3, endpoint |-> 1]}>>,   \* Service 2 Endpoint 1
            <<>>                                                                        \* Service 2 Endpoint 2 
        >>,
        <<
            <<>>,                                                                       \* Service 3 Endpoint 1
            <<{[service |-> 4, endpoint |-> 2]}, {[service |-> 2, endpoint |-> 2]}>>    \* Service 3 Endpoint 2
        >>,
        <<
            <<>>,                                                                        \* Service 4 Endpoint 1
            <<>>
        >>,
        <<
            <<>>
        >>
    >>,
    EndpointWeights <- <<
        <<1, 1>>,
        <<1, 1>>,
        <<1, 1>>,
        <<2, 1>>,
        <<1>>
    >>

Spec == Roshanfer!Spec

AllProcessed == Roshanfer!AllProcessed
Conservation == Roshanfer!Conservation
ABound == Roshanfer!ABound
NsBound == Roshanfer!NsBound

======================================================================

