# sk2sadat - convert ScottKit to Scott Adams DAT format

## Introduction

The sk2sadat compiler for the ScottKit language allows you to write games for the Scott Adams text adventure system with the following advantages:

* Easier to understand error messages
* Automatically fit more data into a game file

## Limitations

Currently doesn't calculate game size in bytes correctly.

Unlike the "official" ScottKit compiler, sk2sadat does not (currently) attempt to stretch larger actions/occurrences across multiple actions. If an action in the ScottKit source code file has too many conditions or commands to fit in a single action in the data file, sk2sadat will fail with an error message.

## Optimizations

To squeeze the most amount of data out of the Scott Adams ".dat" format when compiling a ScottKit source code file, some methods need to be employed.

### Items

Nouns for items that aren't used by actions should be placed last in the noun list, since "autoget" isn't affected by the 150 noun limit that actions have.

### Actions

Messages in actions are limited to 99 entries in "even" command slots (2 and 4). To make sure that this limits the game as little as possible, three methods can be used:

1. Reduce the number of print commands by converting consecutive print commands into a single print command using a single message separated with newlines.
  + Advantage: Allows more messages to escape the 99 message limit
  + Advantage: Reduces the number of used commands in an action
  + Disadvantage: May increase total byte size of messages list.
  + Disadvantage: May increase the total number of messages, possibly hitting the 218 limit of some terps quicker.
2. Move "print" command codes to "odd" command slots (1 and 3) if possible.
3. Make sure that messages used by print command codes in "even" command slots are placed at the beginning of the messages list.

## Thoughs on future improvements

### println

To improve optimizations and reduce the space inside an action, it should be possible to (optionally?) replace `println` with `print ""` . This way, if `println` is used adjacent to a `print` statement (which it often is), the number of commands used in an action could be reduced.

### Statistics

Add an optional statistics view, that shows you how much data you have of different types, to let you know how much of the resources you're using:

* verbs
* nouns for actions (limited to 150)
* nouns dedicated for items
* odd messages
* even messages (limited to 99)
* actions
* items
* rooms
