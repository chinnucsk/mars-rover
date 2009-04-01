-module(steer).
-export([start/0,test/0]).

-include("../include/debug.hrl").
-include("../include/rover.hrl").


test() ->
    test_pov_funcs(),
    ok.


start() ->
    receive
        {start, {Controller, Pathfind}} ->
            ?LOG({"steer started, waiting for initial rover message"}),
            receive
                {rover, Rover} ->
                    ?LOG({"steer waiting for initial goal"}),
                    receive
                        {goal, Goal} ->
                            visualizer ! {oval, Goal, green},
                            maybe_command(Controller, Rover, Goal),
                            ?LOG({"steer entering main loop"}),
                            loop(Controller, Pathfind, Rover, Goal)
                    end
            end
    end.

loop(Controller, Pathfind, Rover, Goal) ->
    receive
        {rover, Rover1} ->
            %% ?LOG({"steer:loop received rover", Rover}),
            SeekSteering = v_add(Rover1#rover.pos, seek(Rover, Goal, 20)),
            visualizer ! {oval, SeekSteering, green, 2},
            visualizer ! {oval, future_pos(Rover), orange, 2},
            visualizer ! {oval, Rover1#rover.pos, blue, 2},

            maybe_command(Controller, Rover1, Goal),
            loop(Controller, Pathfind, Rover1, Goal);
        {goal, Goal1} ->
            ?LOG({"steer:loop new goal:", Goal1}),
            visualizer ! {oval, Goal, yellow},
            visualizer ! {oval, Goal1, green},
            maybe_command(Controller, Rover, Goal1),
            loop(Controller, Pathfind, Rover, Goal1);
        {reset} ->
            receive
                {rover, Rover1} ->
                    ?LOG({"steer waiting for initial goal"}),
                    receive
                        {goal, Goal1} ->
                            visualizer ! {oval, Goal1, green},
                            maybe_command(Controller, Rover1, Goal1),
                            loop(Controller, Pathfind, Rover1, Goal1)
                    end
            end;
        Any ->
            ?LOG({"steer loop: unknown msg", Any}),
            loop(Controller, Pathfind, Rover, Goal)
    end.





maybe_command(Controller, Rover, Goal) ->
    VGoal = to_rover_coordinates(Rover, Goal),

    Turn = correct_turn(
             Rover#rover.turn,
             turn_goal(
               v2turn(VGoal))),

    TargetSpeed = v2speed(VGoal, 20),

    Accel = correct_accel(
              Rover#rover.accel,
              accel_goal(
                Rover#rover.speed,
                %% FIXME: should get MaxSpeed=20 via message from main on bootup instead
                TargetSpeed)),

    if
        (Accel =:= "") and (Turn =:= "") -> void;
        true ->
            Command = list_to_binary(string:join([Accel, Turn, ";"], "")),

            ?LOG({"steer steering: ", Rover#rover.timestamp, {Accel, Turn}, {Rover#rover.speed, TargetSpeed}}),

            Controller ! {command, Command}
    end.





% where will the rover be in 1 second?
future_pos(Rover) ->
    v_add(Rover#rover.pos, velocity(Rover)).


%% vseek(Rover, Steering) ->
%%     coords_to_pov(
%%       Rover#rover.x,
%%       Rover#rover.y,
%%       Rover#rover.dir,
%%       Goal).


%%% seek behaviour according to http://www.red3d.com/cwr/steer/gdc99/
%%
%% desired_velocity = normalize (position - target) * max_speed
%% steering = desired_velocity - velocity
seek(Rover, Target, MaxSpeed) ->
    %% vector pointing from current position to target
    RoverTarget = v_sub(
                Rover#rover.pos,
                Target),
    %% heading with max speed towards target
    DesiredVelocity = v_mul( MaxSpeed, normalize( RoverTarget ) ),
    Steering = v_sub( DesiredVelocity, velocity(Rover) ),
    Steering.


velocity(Rover) ->
    Sin = math:sin(Rover#rover.dir),
    Cos = math:cos(Rover#rover.dir),
    Speed = Rover#rover.speed,
    Vx = Cos * Speed,
    Vy = Sin * Speed,
    {Vx, Vy}.

normalize({X, Y}) ->
    Length = v_len({X, Y}),
    {X/Length, Y/Length}.


%% transforms vector coordinates so that
%% (1,0) will be 1m away directly in front of the rover and
%% (0,1) will be exactly 1m to the left of the rover
to_rover_coordinates(Rover, X) ->
    coordinate_transform(
      Rover#rover.pos,
      -Rover#rover.dir,
      X).

coordinate_transform(NewOrigin, Dir, X) ->
    X1 = v_sub(X, NewOrigin),
    X2 = rotate(Dir, X1),
    X2.

%% rotates vector by Dir
rotate(Dir, {X, Y}) ->
    Sin = math:sin(Dir),
    Cos = math:cos(Dir),
    X1 = X*Cos-Y*Sin,
    Y1 = Y*Cos+X*Sin,
    {X1, Y1}.

%% simple vector algebra helpers
v_add({X1, Y1}, {X2, Y2}) ->
    {X1+X2, Y1+Y2}.
v_sub({X1, Y1}, {X2, Y2}) ->
    {X1-X2, Y1-Y2}.
v_mul(C, {X, Y}) ->
    {C * X, C * Y}.
v_len({X, Y}) ->
    math:sqrt(X*X) + math:sqrt(Y*Y).

v2speed2({Vx, Vy}) ->
    math:sqrt(Vx*Vx, Vy*Vy).



v2turn({Vx, Vy}) ->
    if
        Vx < 0 ->
            if
                Vy =:= 0 -> Vy1 = 100;
                true -> Vy1 = Vy*100
            end;
        true ->
            Vy1 = Vy
    end,
    Vy1.

v2speed({Vx, Vy}, MaxSpeed) ->
    if
        Vx < 0 -> 0;
%%         Vx > (Vy * 7) -> MaxSpeed;
        true ->
            Speed = 10*MaxSpeed / (abs(Vy) / Vx),
            if
                Speed > MaxSpeed -> MaxSpeed;
                true -> Speed
            end
    end.





%%%%% steering

turn_goal(Diff) ->
    HardTresh = 12,
    StraightTresh = 3,
    if
        Diff < (-1*HardTresh) -> "R";
        ((-1*HardTresh) =< Diff) and (Diff < StraightTresh)-> "r";
        ((-1*StraightTresh) =< Diff) and (Diff =< StraightTresh) -> "-";
        (StraightTresh < Diff) and (Diff < HardTresh)-> "l";
        HardTresh < Diff -> "L"
    end.

correct_turn(Cur,Goal) ->
    case Goal of
        Cur -> "";
        "R" -> "r";
        "L" -> "l";
        "r" ->
            if
                Cur =:= "R" -> "l";
                true -> "r"
            end;
        "l" ->
            if
                Cur =:= "L" -> "r";
                true -> "l"
            end;
        "-" ->
            case Cur of
                "L" -> "r";
                "l" -> "r";
                "R" -> "l";
                "r" -> "l"
            end
    end.


accel_goal(CurSpeed, TargetSpeed) ->
    D = abs(CurSpeed - TargetSpeed),
    if
        D < 1 -> "-";
        CurSpeed < TargetSpeed -> "a";
        TargetSpeed < CurSpeed -> "b"
    end.

correct_accel(Cur, Goal) ->
    case Goal of
        Cur -> "";
        "a" -> "a";
        "b" -> "b";
        "-" ->
            case Cur of
                "a" -> "b";
                "b" -> "a"
            end
    end.






test_pov_funcs() ->
    {0,0} = test_pov(0,0,0),
    {0,0} = test_pov(0,0,1),

    {1,0} = test_pov(1,0,0),
    {0,1} = test_pov(0,1,0),

    {0,1} = test_pov(1,0,1),
    {-1,0} = test_pov(0,1,1),
    {0,-1} = test_pov(-1,0,1),
    {1,0} = test_pov(0,-1,1),

    {-1.0,-1.0} = coords_to_pov(1,1,0,{0,0}),
    {0.0,0.0} = coords_to_pov(-1,0,0,{-1,0}),

    coords_to_pov(116.633,-149.557,2.2331334012628097,{109.375,-234.375}),
    coords_to_pov(116,-149,2.2331334012628097,{109,-234}),
    coords_to_pov(100,-150,2.2331334012628097,{100,-250}),
    coords_to_pov(0,0,2.2331334012628097,{0,-100}),
    coords_to_pov(0,0,2.2331334012628097,{0,-100}),
    coords_to_pov(0,0,2.2331334012628097,{0,-1}),
    coords_to_pov(0,0,math:pi()/2,{0,-1}),
    coords_to_pov(0,0,math:pi(),{0,-1}),
    ok.
test_pov(X, Y, E) ->
    {X1, Y1} = coords_to_pov(0, 0, E*(math:pi()/2), {X, Y}),
    {trunc(X1), trunc(Y1)}.

coords_to_pov(Ox, Oy, Dir, {X, Y}) ->
    coordinate_transform({Ox, Oy}, Dir, {X, Y}).

%% coords_to_pov(Ox, Oy, Dir, {X, Y}) ->
%%     X1 = X-Ox,
%%     Y1 = Y-Oy,
%%     Sin = math:sin(Dir),
%%     Cos = math:cos(Dir),
%%     X2 = X1*Cos-Y1*Sin,
%%     Y2 = Y1*Cos+X1*Sin,
%%     %%?LOG({"coords_to_pov: ",{Ox,Oy},Dir,{X,Y},{X1,Y1},{sin,Sin},{cos,Cos},{X2,Y2}}),
%%     {X2, Y2}.

