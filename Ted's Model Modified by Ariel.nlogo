; TO DO:
; * Koalas wait for an opening (IS IN-DANGER? GOOD ENOUGH? OR NEED PROXIMITY TO ACTUAL CAR?)

breed [ cars car ]
breed [ zones zone ]
breed [ koalas koala ]
breed [ koala-exits koala-exit ]

globals [
  lanes               ; a list of the y coordinates of different lanes
  road-patches        ; easy access to all road patches
  crossings           ; number of successful crossings
  koala-deaths        ; number of deaths
  east-entry-patches  ; patch(es) where cars enter from east
  west-entry-patches  ; patch(es) where cars enter from west
  min-reaction-time
  max-reaction-time
  awareness-area-size
]

cars-own [
  speed                ; the current speed of the car
  top-speed            ; the maximum speed of the car (different for all cars)
  target-lane          ; the desired lane of the car
  direction            ; direction car is driving [ (pycor) / abs(pycor) ] -- right (1) or left (-1)
  reaction-time        ; affects danger region size
  braking-decel        ; affects danger region size
  desired-time-spacing ; how close a car wants to be to another car (in ticks), if possible
]

koalas-own [
  crossing-time     ; duration of time needed for koala to cross a single lane
  direction         ; down (1) or up (-1)
]

patches-own [
  intrinsic-pcolor     ; color of the road (in case color ever needs to be switched out temporarily)
]

; Draw road and field and initial cars
to setup
  clear-all
  resize-world (-1 * road-length / 2) road-length / 2 min-pycor max-pycor
  set-default-shape cars "car"
  draw-road
  create-cars-on-patches n-of (car-appearance-rate * ((max-pxcor - min-pxcor) / top-speed-mean)) road-patches
  ;create-or-remove-cars
  reset-ticks
end

to create-cars-on-patches [car-patches]
  ; Create any desired cars that are not yet in existence
  create-cars count car-patches [
    set color car-color
    move-to one-of free car-patches
    set direction abs( pycor ) / pycor
    set xcor (xcor - direction * 0.499)
    set target-lane pycor
    set heading 90 * direction
    set shape ifelse-value heading > 180 [ "car-flipped" ][ "car" ]
    ;set top-speed 0.5 + random-float 0.5
    set top-speed max (list 0.1 (random-normal top-speed-mean top-speed-sd))
    set speed top-speed
    set max-reaction-time average-reaction-time + spread
    set min-reaction-time average-reaction-time - spread
    if min-reaction-time < 0
      [set min-reaction-time 0]
    set reaction-time min-reaction-time + random-float ( max-reaction-time - min-reaction-time )
    set braking-decel min-braking-decel + random-float ( max-braking-decel - min-braking-decel )
    set desired-time-spacing min-car-time-spacing + random-float ( max-car-time-spacing - min-car-time-spacing )
    hatch-zones 1
    [
      hide-turtle
      set color red
      forward [ stopping-distance ] of myself
      ask myself [ create-link-to myself [ set color red set shape "zone-link" ] ] ;; link for danger zone
    ]
    set awareness-area-size (-2 * speed) + 2

    hatch-zones 1 ;; if larger number, the triangles will become thicker as they take up more pixel space
    [
      set shape "awareness-area-funnel"
      set color blue
      set size awareness-area-size
      set ycor [ ycor ] of myself
      set xcor [ xcor ]  of myself
      ask myself [ create-link-to myself [ set color blue hide-link ]
      ]
    ]
  ]
end

; Create number-of-cars cars placed randomly on roads and across lanes
to create-or-remove-cars
  ; This is run each time through the control loop, in case cars need to be added or removed during runtime

  ; make sure we don't have too many cars for the room we have on the road
  ;let entry-patch one-of (patch-set east-entry-patches west-entry-patches) with [ not any? cars in-radius stopping-distance-formula min-reaction-time top-speed-mean min-braking-decel ]
  let entry-patch one-of (patch-set east-entry-patches west-entry-patches) with [ not any? cars with [ [ pycor ] of myself = pycor and patch-x-distance <= (max-car-time-spacing * top-speed-mean) ] ]
  if entry-patch != nobody and count cars < count road-patches and random-float 1.0 <= car-appearance-rate
  [
    ; Create any desired cars that are not yet in existence
    create-cars-on-patches (patch-set entry-patch)
  ]
end

; Create koalas based on koala-appearance-rate
to create-move-and-remove-koalas
  ; This is run each time through the control loop as koalas arrive and depart continuously over the simulation

  ; Any koalas that have crossed the lane can be moved to next lane or removed from road
  ask koalas with [ crossing-time > 0 and crossing-time < ticks ] [
    ; Move ahead one lane width
    set ycor (ycor + ( -1 * direction ) * 2)

    ifelse abs( ycor ) < number-of-lanes
    [
      ; Moved to next lane; schedule crossing time for this new lane
      set crossing-time (ticks + koala-lane-crossing-time)
    ]
    [
      ; Arrived at other end of road; remove koala from system
      ask out-link-neighbors [ die ]
      set crossings (crossings + 1)
      die
    ]
  ]

  ; Decide whether to create a new koala based on appearance-rate parameter
  if random-float 1.0 <= koala-appearance-rate
  [
    ; Create one new koala at a time
    create-koalas 1
    [
      ; looks like a koala head
      set shape "molecule water" set heading 0

      ; koalas show up in random horizontal position
      set xcor random-xcor

      ; half of the koalas go up across road, the other half go down across road
      set direction (ifelse-value ( random-float 1.0 <= 0.5 ) [ 1 ][ -1 ])
      set ycor direction * number-of-lanes

      ; We don't know when they will cross this lane because they wait for an
      ; opportunity to enter the lane when there are no cars. Setting the
      ; ticks to this dummy value will enable the code below that decides whether
      ; the koala will wait to enter or start into the road
      set crossing-time -1 * (ticks - 0.5)
    ]
  ]

  ; Negative crossing times indicate koala is waiting for scheduled time in future
  ; to evaluate whether to enter a lane (koalas do not run directly into cars)
  ask koalas with [ crossing-time < 0 and (-1 * crossing-time) < ticks ]
  [
    ; Scheduled event for evaluation of lane entry
    let targety pycor + direction
    let targetx xcor
    ifelse in-danger?
    [
      ; Cars are ahead, and so schedule a re-evaluation in the future
      ; (negative "crossing-time" indicates waiting for entering a lane)
      set crossing-time -1 * (ticks + koala-wait-time)
    ]
    [
      ; No cars ahead; enter lane and schedule future lane departure (if all goes well)
      set crossing-time ( ticks + koala-lane-crossing-time )

      ; We show that koala has entered a lane by creating a link to a phantom koala
      ; on the other end of this lane ("koala-exit" agent)
      hatch-koala-exits 1 [
        set shape "molecule water"
        hide-turtle
        set ycor [ ycor + ( -1 * direction ) * 2 ] of myself
        ; The "tie" ensures the phantom koala moves with this koala
        ask myself [ create-link-to myself [ set color [ color ] of myself set shape "default" tie ] ]
      ]
    ]
  ]
end

; Checks to see if a koala at the edge of a road/lane has cars in its path ahead in the
; immediately adjacent lane. Reports the cars that put this koala in danger.
to-report dangerous-cars ; turtle/koala reporter/procedure
  ;let targety pycor - direction
  report cars with [ pycor = [ pycor - direction ] of myself and direction * xcor <= direction * [ xcor ] of myself and x-distance < stopping-distance and awareness-area-size < 6 ]
end

; Reports if any cars are putting this koala in danger.
to-report in-danger? ; turtle/koala reporter/procedure
  report any? dangerous-cars
end

; Calculates length of stopping distance for this car based on reaction time and braking characteristics
to-report stopping-distance ; turtle/car procedure
  report stopping-distance-formula reaction-time speed braking-decel
end

; Calculates length of stopping distance for this car based on reaction time and braking characteristics
to-report stopping-distance-formula [ r s b ] ; procedure using reaction-time, speed, and braking-decel
  report r * s + 0.5 * s ^ 2 / b
end

; Determines whether a patch of road can have a car added to it
to-report free [ rd-patches ] ; turtle/car procedure
  let this-car self
  report rd-patches with [
    not any? cars-here with [ self != this-car ]
  ]
end

; Sets up the road patches
to draw-road
  ask patches [
    ; the road is surrounded by green grass of varying shades
    set pcolor green - random-float 0.5
  ]
  set lanes n-values number-of-lanes [ n -> number-of-lanes - (n * 2) - 1 ]
  set road-patches patches with [ member? pycor lanes ]
  set east-entry-patches road-patches with [ pxcor = min-pxcor and pycor > 0 ]
  set west-entry-patches road-patches with [ pxcor = max-pxcor and pycor < 0 ]
  ;set road-patches patches with [ abs pycor <= number-of-lanes ]
  ask patches with [ abs pycor <= number-of-lanes ] [
    ; the road itself is varying shades of grey
    set intrinsic-pcolor grey - 2.5 + random-float 0.25
    set pcolor intrinsic-pcolor
  ]
  draw-road-lines
end

; Sets up the road lines around/in the road patches
to draw-road-lines
  let y (last lanes) - 1 ; start below the "lowest" lane
  while [ y <= first lanes + 1 ] [
    if not member? y lanes [
      ; draw lines on road patches that are not part of a lane
      ifelse abs y = number-of-lanes
        [ draw-line y yellow 0 ]  ; yellow for the sides of the road
        [ draw-line y white 0.5 ] ; dashed white between lanes
    ]
    set y y + 1 ; move up one patch
  ]
end

; Uses a dummy turtle to draw continuous or dashed lines
to draw-line [ y line-color gap ]
  ; We use a temporary turtle to draw the line:
  ; - with a gap of zero, we get a continuous line;
  ; - with a gap greater than zero, we get a dashed line.
  create-turtles 1 [
    setxy (min-pxcor - 0.5) y
    hide-turtle
    set color line-color
    set heading 90
    repeat world-width [
      pen-up
      forward gap
      pen-down
      forward (1 - gap)
    ]
    pen-up
    forward gap
    pen-down
    forward (0.999 - gap)
    die
  ]
end

; Excuted once every control loop ("tick")
to go
  create-or-remove-cars
  create-move-and-remove-koalas
  ask cars [ move-car-forward ]
  ; ask cars with [ patience <= 0 ] [ choose-new-lane ]
  ask cars with [ ycor != target-lane ] [ move-to-target-lane ]
  ask koalas with [ crossing-time > 0 and in-danger? ] [
    set koala-deaths (koala-deaths + 1)
    ask out-link-neighbors [ die ]
    die
  ]
  tick
end

; Moves car (and its stopping-distance phantom) forward
to move-car-forward ; turtle/car procedure
  ; Reset heading and shape just for multi-lane case when it is possible for cars
  ; to move diagonally a bit as they change lanes
  set heading 90 * direction
  set shape ifelse-value heading > 180 [ "car-flipped" ][ "car" ]

  ; Set speed of this car based on the position (and speed) of car in front
  let blocking-cars other cars in-cone (max (list 1 (desired-time-spacing * speed)) + speed) 180 with [ y-distance <= 1 ]
  let blocking-car min-one-of blocking-cars [ distance myself ]
  ifelse blocking-car != nobody and distance blocking-car < desired-time-spacing * speed [
    ; match the speed of the car ahead of you and then slow
    ; down so you are driving a bit slower than that car.
    if distance blocking-car < 1 [ set speed [ speed ] of blocking-car ]
    slow-down-car ((desired-time-spacing * speed) - distance blocking-car)
  ]
  [
    speed-up-car (acceleration)
  ]

  ; Check to see if you are about to drive off the edge of the world
  ifelse (nobody = patch-ahead speed) or ( abs( heading - 90 ) < 1 and (xcor + speed >= max-pxcor + 0.5) ) or ( abs( heading - 90 ) > 90 and (xcor - speed <= min-pxcor - 0.5) )
  [
    ask out-link-neighbors [ die ]
    die
  ]
  [
    forward speed

    ; This moves the phantom car at end of link so that link shape represents danger region for
    ; this car
    ifelse direction > 0
    [
      ask out-link-neighbors [ setxy min (list (max-pxcor + 0.495) ([ xcor + stopping-distance ] of myself)) ycor ]
    ]
    [
      ask out-link-neighbors [ setxy max (list (min-pxcor - 0.495) ([ xcor - stopping-distance ] of myself)) ycor ]
    ]
  ]
end

; Decelerates a car to keep it behind car in front of it
to slow-down-car [ desired-accel ]; turtle/car procedure
  set speed (speed - min (list desired-accel deceleration))
  if speed < 0 [ set speed min (list desired-accel deceleration) ]
  ; every time you hit the brakes, you loose a little patience
  ; set patience patience - 1
end

; Speeds up a car to get closer to top speed
to speed-up-car [ desired-accel ]; turtle/car procedure
  set speed (speed + min (list desired-accel acceleration))
  if speed > top-speed [ set speed top-speed ]
end

; If multi-lane highway turned on, allows cars to pick a new lane to switch to
to choose-new-lane ; turtle/car procedure
  ; Choose a new lane among those with the minimum
  ; distance to your current lane (i.e., your ycor).
  let other-lanes remove ycor lanes
  if not empty? other-lanes [
    let min-dist min map [ y -> abs (y - ycor) ] other-lanes
    let closest-lanes filter [ y -> abs (y - ycor) = min-dist ] other-lanes
    set target-lane one-of closest-lanes
    ; set patience max-patience
  ]
end

; If multi-lane highway turned on, allows cars to pick a new lane to switch to
to move-to-target-lane ; turtle/car procedure
  set heading ifelse-value target-lane < ycor [ 180 ] [ 0 ]
  let blocking-cars other cars in-cone (1 + abs (ycor - target-lane)) 180 with [ x-distance <= 1 ]
  let blocking-car min-one-of blocking-cars [ distance myself ]
  ifelse blocking-car = nobody [
    forward 0.2
    set ycor precision ycor 1 ; to avoid floating point errors
  ] [
    ; slow down if the car blocking us is behind, otherwise speed up
    ifelse towards blocking-car <= 180 [ slow-down-car (deceleration) ] [ speed-up-car (acceleration) ]
  ]
end

; Reports horizontal distance (properly accounting for world wrapping over on itself)
to-report patch-x-distance
  report distancexy [ pxcor ] of myself pycor
end

; Reports horizontal distance (properly accounting for world wrapping over on itself)
to-report x-distance
  report distancexy [ xcor ] of myself ycor
end

; Reports vertical distance
to-report y-distance
  report distancexy xcor [ ycor ] of myself
end

; Gives cars distinguishable colors
to-report car-color
  ; give all cars a blueish color, but still make them distinguishable
  report one-of [ blue cyan sky ] + 1.5 + random-float 1.0
end

; Number of lanes in simulation; can also make this an input
to-report number-of-lanes
  ; To make the number of lanes easily adjustable, remove this
  ; reporter and create a slider on the interface with the same
  ; name. 8 lanes is the maximum that currently fit in the view.
  report 2
end

; Copyright 1998 Uri Wilensky.
; Copyright 2022 Theodore P. Pavlic (modified and signifnicantly extended by Theodore P. Pavlic).
; See Info tab for full copyright and license.
@#$#@#$#@
GRAPHICS-WINDOW
225
10
5493
359
-1
-1
20.0
1
10
1
1
1
0
0
0
1
-131
131
-8
8
1
1
1
ticks
30.0

BUTTON
10
10
75
45
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
150
10
215
45
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
80
10
145
45
go once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

MONITOR
905
430
1012
475
mean car speed
mean [speed] of cars
2
1
11

SLIDER
10
95
215
128
car-appearance-rate
car-appearance-rate
0
1.0
0.49
0.01
1
NIL
HORIZONTAL

PLOT
535
430
905
605
Car Speeds
Time
Speed
0.0
300.0
0.0
0.5
true
true
"" ""
PENS
"average" 1.0 0 -10899396 true "" "plot mean [ speed ] of cars"
"max" 1.0 0 -11221820 true "" "plot max [ speed ] of cars"
"min" 1.0 0 -13345367 true "" "plot min [ speed ] of cars"

SLIDER
10
200
215
233
acceleration
acceleration
0.001
0.01
0.005
0.001
1
NIL
HORIZONTAL

SLIDER
10
230
215
263
deceleration
deceleration
0.01
0.1
0.05
0.01
1
NIL
HORIZONTAL

PLOT
240
431
530
606
Cars Per Lane
Time
Cars
0.0
0.0
0.0
0.0
true
true
"set-plot-y-range (floor (count turtles * 0.4)) (ceiling (count turtles * 0.6))\nforeach range length lanes [ i ->\n  create-temporary-plot-pen (word (i + 1))\n  set-plot-pen-color item i base-colors\n]" "foreach range length lanes [ i ->\n  set-current-plot-pen (word (i + 1))\n  plot count turtles with [ round ycor = item i lanes ]\n]"
PENS

SLIDER
9
410
214
443
min-braking-decel
min-braking-decel
0
10
4.3
0.1
1
NIL
HORIZONTAL

SLIDER
9
442
214
475
max-braking-decel
max-braking-decel
0
10
4.6
0.1
1
NIL
HORIZONTAL

SLIDER
10
130
215
163
top-speed-mean
top-speed-mean
0
1
0.8
.1
1
NIL
HORIZONTAL

SLIDER
10
165
215
198
top-speed-sd
top-speed-sd
0
1
0.5
.1
1
NIL
HORIZONTAL

SLIDER
225
365
420
398
koala-appearance-rate
koala-appearance-rate
0
0.5
0.09
0.01
1
NIL
HORIZONTAL

SLIDER
425
365
637
398
koala-lane-crossing-time
koala-lane-crossing-time
0
500
17.7
0.1
1
NIL
HORIZONTAL

MONITOR
890
365
982
410
NIL
koala-deaths
0
1
11

MONITOR
815
365
887
410
NIL
crossings
0
1
11

MONITOR
985
365
1065
410
kill rate
koala-deaths / ( crossings + koala-deaths )
4
1
11

SLIDER
640
365
812
398
koala-wait-time
koala-wait-time
0
50
6.2
0.1
1
NIL
HORIZONTAL

SLIDER
9
475
214
508
min-car-time-spacing
min-car-time-spacing
0
50
21.8
0.1
1
NIL
HORIZONTAL

SLIDER
9
505
214
538
max-car-time-spacing
max-car-time-spacing
0
50
21.8
0.1
1
NIL
HORIZONTAL

MONITOR
905
515
1040
560
number of cars
count cars
0
1
11

MONITOR
905
560
972
605
east cars
count cars with [ pycor > 0 ]
0
1
11

MONITOR
970
560
1040
605
west cars
count cars with [ pycor < 0 ]
0
1
11

SLIDER
10
55
215
88
road-length
road-length
40
500
263.0
1
1
NIL
HORIZONTAL

SLIDER
19
538
204
571
average-reaction-time
average-reaction-time
0
10
10.0
1
1
NIL
HORIZONTAL

SLIDER
27
573
199
606
spread
spread
0
5
2.0
1
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

This model simulates roadkill interactions in a system with koalas crossing a two-lane
road. Desired speeds and car spacings differ between cars, and each car has a different
(theoretical) reaction time that (with braking characteristics) sets up a "danger zone" in front of each car that is guaranteed to kill a koala that arrives within it. Koalas that arrive to the side of a road with no free road ahead of them will wait to try to cross until there is free road in front of them.

## HOW TO USE IT

Click on the SETUP button to set up the cars. Click on GO to start the cars moving. The GO ONCE button drives the cars for just one tick of the clock.

## COPYRIGHT AND LICENSE

Original traffic model Copyright 1998 Uri Wilensky.

![CC BY-NC-SA 3.0](http://ccl.northwestern.edu/images/creativecommons/byncsa.png)

Modified koala-traffic model Copyright 2012 Theodore Pavlic.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 License.  To view a copy of this license, visit https://creativecommons.org/licenses/by-nc-sa/3.0/ or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

awareness-area-funnel
true
0
Line -955883 false 0 150 150 300
Line -955883 false 150 300 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
true
0
Polygon -7500403 true true 180 0 164 21 144 39 135 60 132 74 106 87 84 97 63 115 50 141 50 165 60 225 150 300 165 300 225 300 225 0 180 0
Circle -16777216 true false 180 30 90
Circle -16777216 true false 180 180 90
Polygon -16777216 true false 80 138 78 168 135 166 135 91 105 106 96 111 89 120
Circle -7500403 true true 195 195 58
Circle -7500403 true true 195 47 58

car-flipped
true
0
Polygon -7500403 true true 120 0 136 21 156 39 165 60 168 74 194 87 216 97 237 115 250 141 250 165 240 225 150 300 135 300 75 300 75 0 120 0
Circle -16777216 true false 30 30 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 220 138 222 168 165 166 165 91 195 106 204 111 211 120
Circle -7500403 true true 47 195 58
Circle -7500403 true true 47 47 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

molecule water
true
0
Circle -1 true false 183 63 84
Circle -16777216 false false 183 63 84
Circle -7500403 true true 75 75 150
Circle -16777216 false false 75 75 150
Circle -1 true false 33 63 84
Circle -16777216 false false 33 63 84

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="Speed Limit Experiment 1" repetitions="5" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="500"/>
    <metric>koala-deaths / ( crossings + koala-deaths )</metric>
    <enumeratedValueSet variable="road-length">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-braking-decel">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-car-time-spacing">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="acceleration">
      <value value="0.005"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-reaction-time">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="koala-appearance-rate">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-braking-decel">
      <value value="8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="koala-wait-time">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="top-speed-mean">
      <value value="0.35"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="top-speed-sd">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-reaction-time">
      <value value="8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-car-time-spacing">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="koala-lane-crossing-time">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="car-appearance-rate">
      <value value="0.11"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="deceleration">
      <value value="0.02"/>
    </enumeratedValueSet>
    <steppedValueSet variable="average-reaction-time" first="1" step="0.5" last="10"/>
    <steppedValueSet variable="spread" first="1" step="0.5" last="5"/>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

awareness-area-link
1.0
-0.2 1 1.0 0.0
0.0 0 0.0 1.0
0.2 1 1.0 0.0
link direction
true
0

awareness-link
0.0
-0.2 1 4.0 4.0
0.0 1 4.0 4.0
0.2 1 4.0 4.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

koala-link
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0

zone-link
0.0
-0.2 1 1.0 0.0
0.0 1 1.0 0.0
0.2 1 1.0 0.0
link direction
true
0
@#$#@#$#@
0
@#$#@#$#@
