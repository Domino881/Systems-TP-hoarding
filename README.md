# Toilet paper hoarding in COVID-19

Group project for module "Systems - the science of everything" by:

Harry Byrne, Dominik Kuczynski, James Hales, Cormac Niland, Molly Robinson

## Documentation

<img src="images/full.png" width="90%">

### Agents

The agents are as follows: 

- <img src="images/person.png" style="vertical-align:middle; width:30px"> Persons

Persons wander around their home location until they run out of toilet paper, in which case
they go to one of the nearest stores to buy some. They can spread fear with their friends as
well as get scared by the media.

- <img src="images/store.png" style="vertical-align:middle; width:30px"> Stores

Stores have a given amount of toilet paper in stock, and they order every month. 

### Parameters

- `maximum-buy-law` &rarr enabling this will limit each person's tp buying to 25 at a time
- `inspect patient zero` &rarr shows the connections "friendships" of one of the most scared persons
- `COVID` &rarr pressing will signicantly increase fear in a number of persons
- `patients-zero` &rarr determines how many persons will be affected by `COVID`
- `isolated?` &rarr determines whether the above mentioned persons will have few friends - be isolated
- `initial-resilience` &rarr sets the initial resilience to fear of all the persons

### Running the model
