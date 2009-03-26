-module(mapquad).
-export([start/1]).

-include("../include/debug.hrl").
-include("../include/quadtree.hrl").


start(Pathfind) ->
    QuadTree = quadtree:new(),
    loop(Pathfind, QuadTree).

loop(Pathfind, QuadTree) ->
    receive
        {new,Item} ->
            QuadTree1 =
                quadtree:insert_circle(
                  QuadTree,
                  Item),
            %% FIXME: we should only send an update to Pathfind
            %% if the quad actually changed here
            Pathfind ! {quadtree, QuadTree1},
            loop(Pathfind, QuadTree1);
        Any ->
            ?LOG({"map:loop received unknown msg", Any}),
            loop(Pathfind, QuadTree)
    end.

