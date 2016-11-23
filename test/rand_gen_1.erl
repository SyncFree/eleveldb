-module(rand_gen_1).
-compile(export_all).

%% !@#$! pareto key generators are not exported from basho_bench_keygen.erl
%%
%% Use a fixed shape for Pareto that will yield the desired 80/20
%% ratio of generated values.

-define(PARETO_SHAPE, 1.5).

%% Create a randomly-generated 16MB binary once, then assign slices of
%% that binary quickly.  If you wish to avoid having easily
%% compressible data in LevelDB (or other backend) chunks, then Size
%% should be much much less than 16MB.

random_bin(_Id, Size) ->
    HunkSize = 16*1024*1024,
    BigHunk = crypto:rand_bytes(HunkSize),
    fun() -> 
            Offset = random:uniform(HunkSize - Size),
            <<_:Offset/binary, Bin:Size/binary, _/binary>> = BigHunk,
            Bin
    end.

%% Make keys that look like this: <<"001328681207_012345">>
%% The suffix part (after the underscore) will be assigned either
%% os:timestamp/0's milliseconds or an integer between 0 and MaxSuffix.
%% The integer between 0 & MaxSuffix will be chosen PercentAlmostSeq
%% percent of the time.

almost_completely_sequential(_Id, MaxSuffix, PercentAlmostSeq) ->
    fun() ->
            {A, B, C} = os:timestamp(),
            TimeT = (A*1000000) + B,
            End = case random:uniform(100) of
                      N when N < PercentAlmostSeq ->
                          C;                    % microseconds
                      _ ->
                          random:uniform(MaxSuffix)
                  end,
            [integer_to_list(TimeT), $_,
             integer_to_list(End)]
    end.

%% Make keys that look like this: <<"001328681207_012345">>.
%%
%% With probability of 1 - (MillionNotSequential/1000000), the keys
%% will be generated using os:timestamp/0, where the suffix is exactly
%% equal to the microseconds portion of os:timestamp/0's return value.
%% Such keys will be perfectly sorted for time series-style keys: each
%% key will be "greater than" any previous key.
%%
%% With probability of (MillionNotSequential/1000000), the key will
%% still have the same "integer1_integer2" form, but the first integer
%% will up to approximately 3 million seconds earlier than the current
%% time_t wall clock time, and the second integer will be generated by
%% random:uniform(1000*1000).
%%
%% As MillionNotSequential approaches zero, the keys generated will
%% become more and more perfectly sorted.

mostly_sequential(_Id, MillionNotSequential) ->
    fun() ->
            {A, B, C} = os:timestamp(),
            {X, Y, Z} = case random:uniform(1000*1000) of
                            N when N < MillionNotSequential ->
                                {A - random:uniform(3),
                                 abs(B - random:uniform(500*1000)),
                                 random:uniform(1000*1000)};
                            _ ->
                                {A, B, C}
                        end,
            TimeT = (X*1000000) + Y,
            %% e.g. 001328681207_012345
            io_lib:format("~12.12.0w_~6.6.0w", [TimeT, Z])
    end.

%% Generate a pareto-distributed integer and then convert it to a
%% binary.  Useful for basho_bench plugins that are expecting its keys
%% be Erlang binary terms.

pareto_as_bin(_Id, MaxKey) ->
    Pareto = pareto(trunc(MaxKey * 0.2), ?PARETO_SHAPE),
    fun() ->
            list_to_binary(io_lib:format("~w", [Pareto()]))
    end.

pareto(Mean, Shape) ->
    S1 = (-1 / Shape),
    S2 = Mean * (Shape - 1),
    fun() ->
            U = 1 - random:uniform(),
            trunc((math:pow(U, S1) - 1) * S2)
    end.

