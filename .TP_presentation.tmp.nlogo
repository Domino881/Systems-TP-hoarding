globals [ city-size tp-desired-stock covid tp-capacity time-covid-started graph-store graph-person plot-all default-color media-scaring media-message media-messages-city
  fear-forget beta media-last-update
  tp-avg-amount tp-use-rate tp-min-amount maximum-buy ]
breed [ persons person ]
breed [ stores store ]
breed [ alerts alert ]

persons-own [ tp-amount destination my-home age fear hoarding hoarding-threshold max-fear]
stores-own [ tp-stock recently-bought recently-ordered sold-out-at last-graphing]

;; __________________________________________________SETUP__________________________________________________
to setup
  clear-all
  set-default-shape persons "person"
  set-default-shape stores "house"
  set-default-shape alerts "x"
  random-seed 8

  ;;------------------------------------------- Global variables -------------------------------------------

  set city-size max-pxcor / 15
  set plot-all true
  set covid false
  set time-covid-started 0 ;;temporary until covid starts
  set maximum-buy-law false
  set maximum-buy 25

  ;; store variables
  set tp-desired-stock 2800
  set tp-capacity 8000

  ;; person variables
  set tp-avg-amount 15
  set tp-use-rate 1
  set tp-min-amount 3
  set fear-forget 0.7
  set alpha 0.4
  set beta 0.15
  set default-color [70 70 70]

  ;; media variables
  set media-scaring 0
  set media-messages-city [ "Fear is spreading in city " "People are worried about toilet paper in city " ]
  set media-message "..."
  set media-last-update 0

  ;;--------------------------------------------------------------------------------------------------------

  create-stores 10
  ask stores [
    set color round ( who * 14 )
    set color color - (color mod 10) + 7

    set size 1.5
    setxy random-xcor random-ycor

    set tp-stock tp-desired-stock
    set recently-ordered tp-stock
    set sold-out-at -40
    set last-graphing 0
  ]
  set graph-store store 1

  create-persons 1000
  ask persons [
    set color default-color
    fd random 25

    ;; pick one of stores to be one's "city"
    ;; get placed with a normal distribution around the city, std dev.=city-size
    let my-city one-of stores
    setxy [xcor] of my-city + random-normal 0.0 city-size [ycor] of my-city + random-normal 0.0 city-size
    set my-home patch-here

    ;; starting tp amount distributed normally around tp-avg-amount
    set tp-amount max list 0  (random-normal tp-avg-amount (0.5 * tp-avg-amount) )

    ;; age distributed normally around 40
    set age max list 20 (random-normal 40 20)

    ;; hoarding-threshold gets greater when youre older -- so younger people hoard more
    set fear 0
    set hoarding False
    set hoarding-threshold 50 + random (age / 4)
    set max-fear random-normal 70 20

    make-friends
  ]
  set graph-person person 10

  ask links [
    set color green
    hide-link
  ]

  reset-ticks
end
;; ________________________________________________________________________________________________________

;; __________________________________________________GO____________________________________________________
to go
  ask persons [ consume-tp ]
  ask persons [ wander ]
  ask persons [ get-scared ]

  ;; fear is spread by links - each "friendship" increases the fear of the less scared person every so often.
  ;; => kind of like the friends meeting up and the more scared person scaring the other
  ask links [ link-spread-fear ]

  ;;stores order stock every month, but on different days
  ask stores [ if (ticks - 200) mod 300 = (10 * who) mod 300 [ order-stock ] ]

  graph
  pick-store-to-graph

  tick
end
;; ________________________________________________________________________________________________________

to make-friends
  ;; run only once, allows person to create links with other persons

  ;; n = number of friends
  let n random 7

  ;; heuristic: when can't find 7 friends, try 10 times before giving up
  ;; (so that the loop doesn't go indefinitely)
  let tries 10

  ;; older people have lower chance of long-distance friends
  let long-dist-chance (0.5 - age / 300 )

  while [ count my-links < n and tries > 0][

    (ifelse random-float 1 < (1 - long-dist-chance )[
      ;; 60% chance for friend from within city
      if count other persons with [ distance myself < city-size and not member? self link-neighbors] > 0 [
        create-link-with one-of other persons with [ distance myself < city-size and not member? self link-neighbors]
      ]
    ][
      ;; 40% chance for long-distance friend
      if count other persons with [ distance myself > city-size and not member? self link-neighbors] > 0 [
        create-link-with one-of other persons with [ distance myself > city-size and not member? self link-neighbors]
      ]
    ])
    set tries (tries - 1)
  ]
end

to consume-tp
  ;;when tp is ending, use more and more slowly (ration)
  set tp-amount tp-amount - 0.1 * tp-use-rate * (1 - exp(-0.5 / tp-min-amount * tp-amount) )
end

to wander
  ;; if at a store, and looking to shop, to so
  if is-store? destination and distance destination < 2 [ shop ]

  ;; if got home, clear destination
  if destination = my-home and patch-here = destination
  [ set destination 0 ]

  ;; if tp ran out, set the destination as one of 3 closest stores
  if ( tp-amount < tp-min-amount or (hoarding and random-float 1 < 0.1) ) and destination = 0
  [ set destination one-of min-n-of 3 stores [ distance myself ] ]

  ;; if has a destination set (store/home), go towards it
  (ifelse destination != 0 [
    face destination
    fd 1
    stop
    ]
  ;; otherwise, walk randomly
    [
      lt random 100
      rt random 100
      fd 0.05
  ])
end

to get-scared
  ;; fear increases chance of hoarding, having a lot of tp at home decreases it
  (ifelse (fear > hoarding-threshold and not hoarding)  [
    if ((fear / 100) - (tp-amount / (8 * tp-avg-amount))) >= (random-float 1) [
      set hoarding True
    ]
  ][
      set hoarding False
  ])
  ;; make color more red when scared
  set color replace-item 0 color min list 255 (70 + 2 * fear)

  ;; become more resistant to fear (forget faster) with time
  if time-covid-started > 0 [set fear-forget min list (2.5 * 0.7) (0.7 * (initial-resilience + ((ticks - time-covid-started) / 1000) ^ 2))]

  set fear fear - fear-forget

  set fear min list max-fear fear
  set fear max list 0 fear
end

to link-spread-fear
  if random-float 1 < 0.01[
    ask min-one-of both-ends [fear][
      if (([fear] of other-end) - fear) > 10[
        set fear fear + (random-float 2) * ([fear] of other-end);;0.2 * ( fear + 3 * maxfear + minfear )
      ]
    ]
  ]
end

to shop
  let this-store one-of stores with [ distance myself < 2.5 ]

  ;; desired-buy is a random (normal) number around tp-avg-amount
  ;; so a person wants to buy about the avg-amount
  let desired-buy max list (tp-min-amount + 7) (random-normal (0.5 * tp-avg-amount) (0.5 * tp-avg-amount) )

  ;; if hoarding, buy (8±2) times the usual amount
  if hoarding[
    set desired-buy max list (tp-min-amount + 7) ( (1 + random-normal 8 2) * (desired-buy) )
  ]

  ;; if there's not enough in the store, just buy all there is
  ;; if there's a max buy law, buy no more than that
  let amount-buying min list desired-buy [tp-stock] of this-store
  if maximum-buy-law [ set amount-buying min list desired-buy maximum-buy ]

  ;; if couldn't buy anything, look for next closest store and increase fear
  if amount-buying = 0 [
    if any? ( stores with [ tp-stock > 0] )[
    let new-dest min-one-of stores with [ tp-stock > 0] [distance myself]
    set destination new-dest
    ]

    set fear min list max-fear (fear + 10)

    ask this-store [ if ticks - sold-out-at > 30 [set sold-out-at ticks] ]
  ]

  set tp-amount tp-amount + amount-buying

  ask this-store [
    set tp-stock tp-stock - amount-buying
    set recently-bought recently-bought + amount-buying
  ]

  if tp-amount > tp-min-amount [ set destination my-home ]
end

to order-stock
  ;; if tp sold out before end of month, predict with factor>=1 how much would have needed
  let factor 1
  if ticks - sold-out-at < 30 and sold-out-at mod 30 != 0  [ set factor 30 / ( sold-out-at mod 30 ) ]

  ;; "learning" parameter: alpha is how much to adjust for last month's sales, beta is to adjust for how much is in storage
  ;; equation: tp-stock = tp-stock + alpha * (last month's sales - how much was ordered) + beta * (desired stock - current stock)

  ;; goal: undercompensate ( because of supply chain inertia, bullwhip effect ), want the stock to oscillate around desired stock

  set tp-stock tp-stock + min list (tp-capacity - tp-stock) (recently-ordered + alpha * (factor * recently-bought - recently-ordered) + beta * (tp-desired-stock - tp-stock) )
  set recently-ordered recently-ordered + alpha * (recently-bought - recently-ordered)  + beta * (tp-desired-stock - tp-stock)

  set recently-bought 0
end

to-report media
  ;; procedure for media headlines

  ;; don't update more often than 200 ticks
  if (ticks - media-last-update) > 200[
    set media-last-update ticks

    ;; report fear in cities
    let fear-stores (stores with [count persons with [distance myself < city-size and fear > 7] > 5])
    (ifelse any? fear-stores [
      ask one-of fear-stores[
        set media-scaring 1
        set media-message word (item (random (length media-messages-city) ) media-messages-city) who
      ]
    ][
      set media-message "..."
      set media-scaring 0
    ])

    ;; scare people through traditional media, old people get scared more
    if media-scaring [ask persons [ set fear fear + (0.004 * age * media-scaring) * (100 - fear) ]]

  ]

  ;; report out of stock
  if (any? stores with [tp-stock = 0]) and (media-scaring != 5 or (ticks - media-last-update) > 200)[
    let store-list ([who] of stores with [tp-stock = 0])
    if length store-list = 1 [
      set media-message word "Breaking news: no toilet paper in store "  (but-first but-last word "" store-list)
      set media-scaring 3
    ]
    if length store-list > 1 [
      set media-message "Breaking news: toilet paper shortage!"
      set media-scaring 5
    ]
    ;;set media-last-update ticks
  ]

  if empty? media-message [ report "..." ]
  report media-message
end

to graph
  set-current-plot "tp stock"
  ask stores [
    if plot-all [
      set-current-plot-pen word "pen-" who
      set-plot-pen-color color
      plot tp-stock
    ]
    if tp-stock <= 0 [
      hatch-alerts 1 [ set color black ]
    ]
    if tp-stock > 0 [ ask alerts-here [die] ]


    ;;set label precision tp-stock 0
  ]

  if not plot-all[
    ask graph-store[
      ;;set color yellow
      set-current-plot-pen word "pen-" who
      plot tp-stock
    ]
  ]

  set-current-plot "TP rolls in someone's house"
  ask graph-person[
    plot ceiling tp-amount
  ]
end

to pick-store-to-graph
  if mouse-down? and mouse-inside? and not plot-all [
    ask patch mouse-xcor mouse-ycor [
      if not member? graph-store stores with-min [ distance patch mouse-xcor mouse-ycor ][
        print [last-graphing] of graph-store
        ask graph-store [ set last-graphing ticks ]
        set graph-store one-of stores with-min [ distance patch mouse-xcor mouse-ycor ]
        set-current-plot "tp stock"
        set-current-plot-pen word "pen-" [who] of graph-store
        repeat (plot-x-max + plot-x-min  ) / 2 - [last-graphing] of graph-store [ plot 0 ]
      ]
    ]
  ]

end

to-report people-hoarding
  report count persons with [hoarding]
end

to-report avg-stock
  report mean [ tp-stock ] of stores
end

to-report average-fear
  let avg-fear mean [ fear ] of persons
  report avg-fear
end

to-report resilience
  report fear-forget / 0.7
end
@#$#@#$#@
GRAPHICS-WINDOW
370
114
916
675
-1
-1
14.541
1
10
1
1
1
0
1
1
1
0
36
0
37
1
1
1
ticks
30.0

BUTTON
10
10
75
43
setup
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
10
50
75
83
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

PLOT
940
232
1391
622
tp stock
NIL
NIL
0.0
10.0
-100.0
10000.0
false
true
"set-plot-x-range -250 250\nset-plot-background-color black" "set-plot-x-range plot-x-min + 1 plot-x-max + 1\nset-plot-y-range 0 tp-capacity"
PENS
"pen-0" 1.0 0 -7500403 false "" ""
"pen-1" 1.0 0 -2674135 false "" ""
"pen-2" 1.0 0 -955883 false "" ""
"pen-3" 1.0 0 -6459832 false "" ""
"pen-4" 1.0 0 -1184463 false "" ""
"pen-5" 1.0 0 -10899396 false "" ""
"pen-6" 1.0 0 -13840069 false "" ""
"pen-7" 1.0 0 -14835848 false "" ""
"pen-8" 1.0 0 -11221820 false "" ""
"pen-9" 1.0 0 -13791810 false "" ""
"pen-10" 1.0 0 -13345367 false "" ""
"zero" 10.0 0 -8630108 true "" "plot 0"
"desired" 10.0 0 -5825686 true "" "plot tp-desired-stock"
"graph-store" 1.0 0 -2064490 false "" ""
"capacity" 10.0 0 -16777216 true "" "plot tp-capacity"

BUTTON
7
102
169
135
inspect patient zero
;;set graph-person max-one-of persons [ fear ]\n;;ask graph-person [ set color [ 0 255 0 ] ]\n;;inspect graph-person\nask graph-person [ ask my-links [show-link ] ]\nset-current-plot \"TP rolls in someone's house\"\nplot-pen-reset\nset-plot-x-range -250 250
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
25
439
341
599
TP rolls in someone's house
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"set-plot-x-range -250 250\nset-plot-background-color black" "set-plot-x-range plot-x-min + 1 plot-x-max + 1\n;;set-plot-y-range 0 tp-avg-amount + tp-min-amount + 2"
PENS
"pen-0" 1.0 0 -1 true "" ""

BUTTON
943
10
1143
65
COVID
set covid not covid\n  \n  (ifelse isolated? [\n    ask n-of Patients-zero persons with [count my-links < 2][\n      set fear 100\n    ]\n  ][\n    ask n-of Patients-zero persons with [count my-links > 3][\n      set fear 100\n    ]\n  ])\n  \n  if time-covid-started = 0[\n    set time-covid-started ticks + 1\n  ]\n\n  ask persons with [fear = 100] [ set color [ 255 0 0 ] ]\n  set graph-person one-of persons with [fear > 90]
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
1281
627
1390
660
toggle plot all
set plot-all not plot-all\nset-current-plot \"tp stock\"\nif plot-all[\nask stores with [who != [who] of graph-store][\n  set-current-plot-pen word \"pen-\" who\n  repeat (plot-x-max + plot-x-min  ) / 2 - last-graphing [ plot 0 ]\n]\n]\nif not plot-all[\n  ask stores with [who != [who] of graph-store][\n    set last-graphing ticks\n  ]\n]\n;;clear-plot\n;;set-plot-x-range -250 250
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
9
148
362
426
Average fear level
NIL
NIL
0.0
10.0
-0.5
10.0
true
false
"set-plot-x-range -1000 400\nset-plot-background-color black" "set-plot-x-range plot-x-min + 1 plot-x-max + 1"
PENS
"default" 1.0 0 -2674135 true "" "plot average-fear"

MONITOR
355
10
929
111
TP News
media
0
1
25

MONITOR
132
620
236
665
NIL
people-hoarding
0
1
11

SLIDER
940
628
1112
661
alpha
alpha
0
2
0.4
0.01
1
NIL
HORIZONTAL

SLIDER
945
77
1143
110
Patients-zero
Patients-zero
0
10
1.0
1
1
NIL
HORIZONTAL

SWITCH
1149
77
1254
110
isolated?
isolated?
1
1
-1000

SWITCH
152
29
311
62
maximum-buy-law
maximum-buy-law
1
1
-1000

SLIDER
1119
176
1291
209
initial-resilience
initial-resilience
0
2
1.0
0.1
1
NIL
HORIZONTAL

MONITOR
1302
154
1390
219
NIL
resilience
1
1
16

@#$#@#$#@
## WHAT IS IT?

This model simulates points of information and/or resource exchange in an urban environment. An urban environment is assumed to be a pedestrian friendly city-space where people normally encounter one another on a face-to-face basis; and, typically encounter informational systems (such as advertising) and exchange systems (such as consumer based shopping).

The object of the model is to simulate people's awareness of the value of exchanging resources, and evaluate the influence "aware" people have on one another, and on their environment in an information-rich context such as a city.

## HOW IT WORKS

The model determines a person's theoretical level of "awareness" within an urban environment based upon a person's random encounter with information centers. In the model, information centers are any source of positive information exchange such as an advertisement (for a public good) or a recycling center. In general terms, "awareness" involves a person showing realization, perception, or knowledge.

In this model, each person has some amount of "awareness", which is measured in "awareness points".  There is a discrete set of "levels" of awareness that people may attain.  A person may be "unaware" (0 - 5 points), "aware" (5 - 10 points), "well-informed" (10 - 15 points), or an "activist" (more than 15 points).

To gain awareness, a person either runs into a center, where they gain five awareness points; or is influenced by a person who is well-informed or an activist, where they gain one awareness point. If one of these events does not occur during a given time step (tick), the person will lose one awareness point (down to zero).  In this model, there is no such thing as "negative awareness".

(The idea of negative awareness may sound ridiculous, but it could make sense in some situations -- for instance, if some faction is spreading information that is in direct conflict to another faction, and people may come into contact with information and advertising promoting either position.  That is, negative awareness might represent "subscription to an opposing and irreconcilable viewpoint".  For instance, in the United States, there are activists working both for and against the legality of abortion.)

When a person becomes an activist (15 awareness points), a new center is formed.  The new information centers are colored blue, whereas the initial information centers are green.

If no one comes into contact with a center for a specified amount of time (see the NON-USAGE-LIMIT slider), the center disappears from the world.  The intuition here is that if an information/advertising method or location is yielding no fruit, eventually it will be shut down.

## HOW TO USE IT

Press SETUP and then GO.

The PEOPLE slider determines how many people "agents" are randomly distributed in the initial setup phase of the model

The CENTERS slider determines how many information centers are randomly distributed in the initial setup of the model.

The NON-USAGE-LIMIT determines how many ticks a center can go unused before being shut down.

Use the PLACE-CENTERS button to manually place information centers on the view (by clicking their locations with the mouse, while the PLACE-CENTERS button is turned on).

There are also numerous monitors that display information about the current state of the world, such as the current breakdown of awareness in the population, via the ACTIVIST, "WELL INFORMED", AWARE, and UNAWARE monitors.

The CENTERS monitor tells how many information centers are present in the world.

The AVG. NON-USAGE monitor tells the average number of ticks it has been since each of the information centers has been used (i.e. influenced a person).

The AVERAGE STATE OF AWARENESS monitor tells the average number of awareness points that people in the population have.

The LEVELS OF AWARENESS plot shows the history of how many people were at each level of awareness at each tick of the model, and the AVG. AWARENESS plot keeps track of the average awareness of the population over time.

## THINGS TO NOTICE

The initial relative density of people to centers is vital to achieving systemic balance. The model simulates a complex system of data exchange by exploring positive feedback; and the model was created as a lens to describe one important process of emergent pattern formation in a sustainable city.  Specifically, the model allows us to study and discuss the important relationship between a population and its ability to learn and become participatory in the building of its own environment. Here are some questions to encourage discussion about the model and the topics it broaches.

Is there a minimum number of people or centers needed to eventually make everyone an activist?  Does it happen suddenly or gradually?  You can see this both visually, and it is represented in both the LEVELS OF AWARENESS plot, and the AVG. AWARENESS plot.

Where do new information centers tend to form?

What if you only look at the number of "aware" or "well-informed" people over time -- what does that plot look like?  Can you explain its shape?

## THINGS TO TRY

Run the model with 200 PEOPLE, 50 CENTERS, and 100 ticks for the NON-USAGE-LIMIT.  Now try decreasing the NON-USAGE-LIMIT slider.  How low can you go before global awareness isn't achieved?  Does it help to raise the initial number of people or centers?

Try manually placing 20 centers (using the PLACE-CENTERS button) spread out across the world, and run the model.  Now try manually placing just 5 centers, but in a tight cluster.  What are the results?  Do you think this result is realistic, or is indicative of a faulty model of how awareness and activism occurs?

## EXTENDING THE MODEL

Try changing the model so that it simulates two competing and opposed viewpoints (such as legalizing marijuana, or perhaps something more broad, such as Republican versus Democrat politics).  Do this by allowing negative awareness, and have people with less than -15 awareness points be anti-activists, etc.

What if there were more than two opposing points of view?

## NETLOGO FEATURES

It is very common in agent-based models to initialize the setup of the model by positioning agents randomly in the world.  NetLogo makes it easy to move an agent to a random location, with the following code: "SETXY RANDOM-XCOR RANDOM-YCOR".

## RELATED MODELS

This model is related to all of the other models in the "Urban Suite".

This model is also similar to the Rumor Mill model, which is found in the NetLogo models library.

## CREDITS AND REFERENCES

The original version of this model was developed during the Sprawl/Swarm Class at Illinois Institute of Technology in Fall 2006 under the supervision of Sarah Dunn and Martin Felsen, by the following students: Eileen Pedersen, Brian Reif, and Susana Odriozola.  See http://www.sprawlcity.us/ for more information about this course.

Further modifications and refinements were made by members of the Center for Connected Learning and Computer-Based Modeling before releasing it as an Urban Suite model.

The Urban Suite models were developed as part of the Procedural Modeling of Cities project, under the sponsorship of NSF ITR award 0326542, Electronic Arts & Maxis.

Please see the project web site ( http://ccl.northwestern.edu/cities/ ) for more information.

## HOW TO CITE

If you mention this model or the NetLogo software in a publication, we ask that you include the citations below.

For the model itself:

* Felsen, M. and Wilensky, U. (2007).  NetLogo Urban Suite - Awareness model.  http://ccl.northwestern.edu/netlogo/models/UrbanSuite-Awareness.  Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

Please cite the NetLogo software as:

* Wilensky, U. (1999). NetLogo. http://ccl.northwestern.edu/netlogo/. Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

## COPYRIGHT AND LICENSE

Copyright 2007 Uri Wilensky.

![CC BY-NC-SA 3.0](http://ccl.northwestern.edu/images/creativecommons/byncsa.png)

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 License.  To view a copy of this license, visit https://creativecommons.org/licenses/by-nc-sa/3.0/ or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

Commercial licenses are also available. To inquire about commercial licenses, please contact Uri Wilensky at uri@northwestern.edu.

<!-- 2007 Cite: Felsen, M. -->
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
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

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
NetLogo 6.3.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
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
@#$#@#$#@
0
@#$#@#$#@
