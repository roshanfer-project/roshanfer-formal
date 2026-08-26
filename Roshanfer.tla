------------------------ MODULE Roshanfer ------------------------
EXTENDS Sequences, FiniteSets, Utils, Integers, Bags

CONSTANTS 
    EndpointLimits, 
    GlobalLimits,
    ServerDownstreams,
    EndpointWeights

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

RECURSIVE Reach(_)
Reach(se) == 
    LET ReachH(base, next) == 
        base \cup next \cup FoldSet(MapSet(next, Reach), \cup, {})
    IN FoldSeq(ServerDownstreams[se.service][se.endpoint], ReachH, {}) 

ServiceMap(se) == se.service

RECURSIVE TotalEndpointPathLimit(_, _)
TotalEndpointPathLimit(s, e) == 
    LET 
        setHelp(x, y) == x + TotalEndpointPathLimit(y.service, y.endpoint)
        mapHelp(v) == FoldSet(v, setHelp, 0)
    IN EndpointLimits[s][e] + SeqSum(MapSeq(ServerDownstreams[s][e], mapHelp))

GetMessage(fm) == fm.message
DownstreamMsgs(s, e) ==
    LET 
        mapHelp(v) == MapSet(FoldSet({(DOMAIN v[x]) : x \in DOMAIN v}, \cup, {}), GetMessage)
    IN FoldSeq(MapSeq(Downstream[s][e], mapHelp), \cup, {})

IngressVars == <<Pending, Granted, Done, Waiting>>
AgentVars == <<CreditRequestQueues, Cs, Ns, Downstream, Requested>>
ServerVars == <<Processing>>
vars == <<
        Pending, Granted, Done, Waiting, 
        CreditRequestQueues, Cs, Ns, Downstream, Requested, 
        Processing>>

Ingress == 0
Frontend == 1
NAPIs == Len(ServerDownstreams[Frontend])
APIs == 1..NAPIs
NServers == Len(EndpointLimits)
NumberOfMessages == [n \in APIs |-> TotalEndpointPathLimit(1, n)]
Servers == 1..NServers
Agents == Servers
NEndpoints == [n \in Servers |-> Len(ServerDownstreams[n])]
Endpoints == [n \in Servers |-> 1..NEndpoints[n]]
Messages == [n \in APIs |-> [id : 1..NumberOfMessages[n], api : {n}]]
NStages == [
    x \in Servers |-> [
        y \in Endpoints[x] |-> Len(ServerDownstreams[x][y])
    ]
]
Stages == [x \in Servers |-> [y \in Endpoints[x] |-> 1..NStages[x][y]]]
TotalServerDownstreams == [
    x \in Servers |-> [
        y \in Endpoints[x] |-> FoldSeq(ServerDownstreams[x][y], \cup, {})
    ]
]
CumulativeEndpointWeights == [
    x \in DOMAIN EndpointWeights |->
        LET mapHelp(n) == SeqSum(SubSeq(EndpointWeights[x], 1, n))
        IN MapSeq([n \in DOMAIN EndpointWeights[x] |-> n], mapHelp)
]
CumulativeEndpoints(s) == 
    LET f[x \in Servers] ==
        IF x = 1 THEN NEndpoints[1] 
        ELSE NEndpoints[x] + f[x - 1]
    IN f[s]
EndpointIndex(s, e) == IF s = 1 THEN e ELSE CumulativeEndpoints(s - 1) + e
Acyclic == \A s \in Servers : \A e \in Endpoints[s] : 
    [service |-> s, endpoint |-> e] \notin Reach([service |-> s, endpoint |-> e])
ASSUME Acyclic

InitialiseIngress(v) == [x \in APIs |-> v]
Initialise(v) == [x \in Servers |-> v]
InitialiseEndpoint(v) == [x \in Servers |-> [y \in Endpoints[x] |-> v]]
InitialiseStage(v) == [x \in Servers |-> [y \in Endpoints[x] |-> [z \in Stages[x][y] |-> v]]]
InitialiseDownstreams(v) ==     
    [x \in Servers |-> 
        [y \in Endpoints[x] |->
            [z \in Stages[x][y] |-> 
                [s \in MapSet(ServerDownstreams[x][y][z], ServiceMap) |-> v]
            ]
        ]
    ]
Alter(old, i, v) == old' = [old EXCEPT ![i] = v]
AlterEndpoint(old, i, e, v) == old' = [old EXCEPT ![i][e] = v]
AlterStaged(old, i, e, s, v) == old' = [old EXCEPT ![i][e][s] = v]

GrantEnabled(s) ==
    /\
        \/ ServerDownstreams[s] # <<>>
        \/ SeqSum(Ns[s]) < GlobalLimits[s]
    /\ \E e \in Endpoints[s] :
        /\ Ns[s][e] < EndpointLimits[s][e]
        /\ CreditRequestQueues[s][e] # <<>>

ActiveAtServerEndpointH(proc) ==
    LET foldH(m, v) == m + BagCardinality(v) 
    IN FoldSeq(proc, foldH, 0)
ActiveAtServerEndpoint(s, e) == ActiveAtServerEndpointH(Processing[s][e])

ActiveAtServer(s) == SeqSum(MapSeq(Processing[s], ActiveAtServerEndpointH))

ActiveMessages == SeqSum(MapSeq(Granted, Cardinality))

--------------------------------------------------------------------------------------

IngressInit ==
    /\ Pending = InitialiseIngress({})
    /\ Granted = InitialiseIngress({})
    /\ Done = InitialiseIngress({})
    /\ Waiting = MapSeq(Messages, SetToSeq)

AgentInit == 
    /\ Ns = InitialiseEndpoint(0)
    /\ CreditRequestQueues = InitialiseEndpoint(<<>>)
    /\ Cs = Initialise(-1)
    /\ Downstream = InitialiseDownstreams(EmptyBag)
    /\ Requested = InitialiseDownstreams(EmptyBag)

ServerInit ==
    /\ Processing = [x \in Servers |-> [y \in Endpoints[x] |-> [p \in 1..(NStages[x][y] + 1) |-> EmptyBag]]]

IngressCreditRequest(api) ==
    /\ Waiting[api] # <<>>
    /\ Pending[api] = Granted[api]
    /\ AlterEndpoint(
        CreditRequestQueues, 
        Frontend, 
        api, 
        Append(
            CreditRequestQueues[Frontend][api], 
            [message |-> Head(Waiting[api]), upstreamService |-> Ingress, upstreamEndpoint |-> 0, stage |-> 1]
        ))
    /\ Waiting' = [Waiting EXCEPT ![api] = Tail(@)]
    /\ Pending' = [Pending EXCEPT ![api] = @ \cup {Head(Waiting[api])}]
    /\ UNCHANGED <<Granted, Done, Cs, Ns, Downstream, Requested, Processing>>

CreditRequest(s, e) ==
    /\ ServerDownstreams[s][e] # <<>>
    /\ \E stage \in Stages[s][e] : \E fullMessage \in DOMAIN Processing[s][e][stage] :
        /\ Processing[s][e][stage] # EmptyBag
        /\ 
            LET 
                message == fullMessage.message
                agents == MapSet(ServerDownstreams[s][e][stage], ServiceMap)
            IN 
                /\ AlterStaged(Processing, s, e, stage, Processing[s][e][stage] (-) SetToBag({fullMessage}))
                /\ CreditRequestQueues' = [
                    v \in DOMAIN CreditRequestQueues |-> 
                        IF v \in agents THEN  
                            LET 
                                dse == CHOOSE p \in ServerDownstreams[s][e][stage] : p.service = v
                                de == dse.endpoint
                            IN
                                [CreditRequestQueues[v] EXCEPT ![de] = 
                                    Append(@, [
                                        message |-> message, 
                                        upstreamService |-> s, 
                                        upstreamEndpoint |-> e, 
                                        stage |-> stage])
                                ]
                        ELSE
                            CreditRequestQueues[v]
                    ]
                /\ AlterStaged(Requested, s, e, stage, [
                        v \in DOMAIN Requested[s][e][stage] |-> Requested[s][e][stage][v] (+) SetToBag({fullMessage})])
    /\ UNCHANGED <<Pending, Granted, Done, Waiting, Cs, Ns, Downstream>>

RECURSIVE ScheduleGrantH(_, _)
ScheduleGrantH(s, c) ==
    LET
        trueC == c % CumulativeEndpointWeights[s][Len(EndpointWeights[s])]
        e == CHOOSE n \in 1..Len(EndpointWeights[s]) :
            /\ trueC < CumulativeEndpointWeights[s][n]
            /\ 
                \/ n = 1
                \/ 
                    /\ n # 1
                    /\ trueC \geq CumulativeEndpointWeights[s][n-1]
    IN
        IF 
            /\ Ns[s][e] < EndpointLimits[s][e]
            /\ CreditRequestQueues[s][e] # <<>>
        THEN 
            [e |-> e, c |-> trueC]
        ELSE 
            ScheduleGrantH(s, trueC + 1)

ScheduleGrant(s) == ScheduleGrantH(s, Cs[s] + 1)

FrontendCreditGrant ==
    /\ GrantEnabled(Frontend)
    /\ 
        LET 
            ec == ScheduleGrant(Frontend)
            e == ec.e
            c == ec.c
            fullMessage == Head(CreditRequestQueues[Frontend][e])
            message  == fullMessage.message
            upstreamService == fullMessage.upstreamService
            upstreamEndpoint == fullMessage.upstreamEndpoint
            upstreamStage == fullMessage.stage
        IN 
            /\ Alter(Cs, Frontend, c)
            /\ AlterEndpoint(CreditRequestQueues, Frontend, e, Tail(CreditRequestQueues[Frontend][e]))
            /\ AlterStaged(Processing, Frontend, e, 1, Processing[Frontend][e][1] (+) SetToBag({fullMessage}))
            /\ AlterEndpoint(Ns, Frontend, e, Ns[Frontend][e] + 1)
            /\ Alter(Granted, e, Granted[e] \cup {message})
            /\ UNCHANGED <<Pending, Done, Waiting, Downstream, Requested>>

CreditGrant(s) ==
    /\ GrantEnabled(s)
    /\ 
        LET 
            ec == ScheduleGrant(s)
            e == ec.e
            c == ec.c
            fullMessage == Head(CreditRequestQueues[s][e])
            message  == fullMessage.message
            upstreamService == fullMessage.upstreamService
            upstreamEndpoint == fullMessage.upstreamEndpoint
            upstreamStage == fullMessage.stage
            moreUpstream == \E other \in ServerDownstreams[upstreamService][upstreamEndpoint][upstreamStage] :
                /\ 
                    \/ other.service # s
                    \/ other.endpoint # e 
                /\ 
                    \E m \in DOMAIN Requested[upstreamService][upstreamEndpoint][upstreamStage][other.service] : 
                        m.message = message
            upstreamMessage == CHOOSE m \in DOMAIN Requested[upstreamService][upstreamEndpoint][upstreamStage][s] : 
                m.message = message
        IN 
            /\ Alter(Cs, s, c)
            /\ AlterEndpoint(CreditRequestQueues, s, e, Tail(CreditRequestQueues[s][e]))
            /\ AlterStaged(Requested, upstreamService, upstreamEndpoint, upstreamStage, 
                [Requested[upstreamService][upstreamEndpoint][upstreamStage] EXCEPT ![s] = 
                    @ (-) SetToBag({upstreamMessage})])
            /\ AlterStaged(Processing, s, e, 1, Processing[s][e][1] (+) SetToBag({fullMessage}))
            /\
                \/
                    /\ moreUpstream
                    /\ AlterEndpoint(Ns, s, e, Ns[s][e] + 1)
                \/
                    /\ ~moreUpstream
                    /\ Ns' = [Ns EXCEPT ![s][e] = @ + 1, ![upstreamService][upstreamEndpoint] = @ - 1]
            /\ AlterStaged(
                Downstream, 
                upstreamService, 
                upstreamEndpoint, 
                upstreamStage, 
                [Downstream[upstreamService][upstreamEndpoint][upstreamStage] EXCEPT 
                    ![s] = @ (+) SetToBag({upstreamMessage})])
            /\ UNCHANGED <<Pending, Granted, Done, Waiting>>

FrontendServerResponse(e) ==
    /\ Processing[Frontend][e][NStages[Frontend][e] + 1] # EmptyBag
    /\ \E fullMessage \in DOMAIN Processing[Frontend][e][NStages[Frontend][e] + 1] :
        LET 
            stage == NStages[Frontend][e] + 1
            message == fullMessage.message
            upstreamService == fullMessage.upstreamService
            upstreamEndpoint == fullMessage.upstreamEndpoint
            upstreamStage == fullMessage.stage
        IN
            
            /\ AlterStaged(Processing, Frontend, e, stage, Processing[Frontend][e][stage] (-) SetToBag({fullMessage}))
            /\ AlterEndpoint(Ns, Frontend, e, Ns[Frontend][e] - 1)
            /\ Alter(Done, e, Done[e] \cup {message})
            /\ Alter(Pending, e, Pending[e] \ {message})
            /\ Alter(Granted, e, Granted[e] \ {message})
            /\ UNCHANGED <<Waiting, CreditRequestQueues, Cs, Downstream, Requested>>

ServerResponse(s, e) ==
    /\ Processing[s][e][NStages[s][e] + 1] # EmptyBag
    /\ \E fullMessage \in DOMAIN Processing[s][e][NStages[s][e] + 1] :
        LET 
            stage == NStages[s][e] + 1
            message == fullMessage.message
            upstreamService == fullMessage.upstreamService
            upstreamEndpoint == fullMessage.upstreamEndpoint
            upstreamStage == fullMessage.stage
            moreDownstream == \E other \in ServerDownstreams[upstreamService][upstreamEndpoint][upstreamStage] : 
                /\ 
                    \/ other.service # s
                    \/ other.endpoint # e 
                /\
                    \/ \E m \in DOMAIN Downstream[upstreamService][upstreamEndpoint][upstreamStage][other.service] : 
                        m.message = message
                    \/ \E m \in DOMAIN Requested[upstreamService][upstreamEndpoint][upstreamStage][other.service] : 
                        m.message = message
            upstreamMessage == 
                CHOOSE fm \in DOMAIN Downstream[upstreamService][upstreamEndpoint][upstreamStage][s] : 
                    fm.message = message
        IN
            /\
                \/
                    /\ moreDownstream
                    /\ AlterEndpoint(Ns, s, e, Ns[s][e] - 1)
                    /\ AlterStaged(Processing, s, e, stage, Processing[s][e][stage] (-) SetToBag({fullMessage}))
                \/  
                    /\ ~moreDownstream
                    /\ Ns' = [Ns EXCEPT ![s][e] = @ - 1, ![upstreamService][upstreamEndpoint] = @ + 1]
                    /\ Processing' = [Processing EXCEPT 
                        ![s][e][stage] = @ (-) SetToBag({fullMessage}),
                        ![upstreamService][upstreamEndpoint][upstreamStage + 1] = 
                            @ (+) SetToBag({upstreamMessage})]
            /\ AlterStaged(Downstream, upstreamService, upstreamEndpoint, upstreamStage, [
                    Downstream[upstreamService][upstreamEndpoint][upstreamStage] EXCEPT ![s] = 
                        @ (-) SetToBag({upstreamMessage})])
            /\ UNCHANGED <<Pending, Granted, Done, Waiting, CreditRequestQueues, Cs, Requested>>

---------------------------------------------------------------

Init ==
    /\ IngressInit
    /\ AgentInit
    /\ ServerInit

Actions == 
    \/ FrontendCreditGrant
    \/ \E e \in APIs : 
        \/ IngressCreditRequest(e)
        \/ FrontendServerResponse(e)
    \/ \E s \in Servers :
        \E e \in Endpoints[s] : CreditRequest(s, e)
    \/ \E s \in Servers \ {Frontend} :
        \/ CreditGrant(s)
        \/ \E e \in Endpoints[s] : ServerResponse(s, e)

Next ==
    \/ Actions
    \/ 
        /\ \A e \in APIs : Done[e] = Messages[e] 
        /\ \A s \in Servers : \A e \in Endpoints[s] : Ns[s][e] = 0
        /\ UNCHANGED vars

ActionFairness == WF_vars(Actions)

Spec == Init /\ [][Next]_vars /\ ActionFairness

---------------------------------------------------------------

AllProcessed == <>[](\A n \in APIs : Done[n] = Messages[n])

Conservation ==
    \A s \in Servers : \A e \in Endpoints[s] : 
        LET 
            se == [service |-> s, endpoint |-> e]
        IN (
            /\ CreditRequestQueues[s][e] # <<>>
            /\ Ns[s][e] \geq EndpointLimits[s][e]
        ) => \E ose \in {se} \cup Reach(se) : 
                \/ ActiveAtServerEndpoint(ose.service, ose.endpoint) \geq EndpointLimits[ose.service][ose.endpoint] 
                \/ \E o \in TotalServerDownstreams[ose.service][ose.endpoint] : GrantEnabled(o.service)

ABound == \A s \in Servers : \A e \in Endpoints[s] : ActiveAtServerEndpoint(s, e) \leq Ns[s][e]

NsBound == \A s \in Servers : \A e \in Endpoints[s] : Ns[s][e] \leq TotalEndpointPathLimit(s, e)

THEOREM Spec => 
    /\ AllProcessed
    /\ []Conservation
    /\ []ABound
    /\ []NsBound

=============================================================

