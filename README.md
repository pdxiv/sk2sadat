# sk2sadat - convert ScottKit to Scott Adams DAT format

## Introduction

The sk2sadat compiler for the ScottKit language allows you to write games for the Scott Adams text adventure system with the following advantages:

* Easier to understand error messages
* Automatically fit more data into a game file

## How to use

Simply download the `sk2sadat.pl` file to wherever you want to use it. 

Assuming that you have `sk2sadat.pl` in the same directory as a ScottKit source code file called `mygameproject.sck` and you want to make a game file called `mygameproject.dat`, the following commandline should work in Linux or MacOS (in Windows, you'd probably want to replace the `./` with `perl ` in the beginning):

```bash
./sk2sadat.pl mygameproject.sck > mygameproject.dat
```

## Optimizations

To squeeze the most amount of data out of the Scott Adams ".dat" format when compiling a ScottKit source code file, some methods are to be employed.

### Items

Nouns for items that aren't used by actions are placed last in the noun list, since "autoget" isn't affected by the 150 noun limit that actions have.

### Actions

Messages in actions are limited to 99 entries in "even" command slots (2 and 4). To make sure that this limits the game as little as possible, three methods can be used:

1. Reduce the number of print commands by converting consecutive print commands into a single print command using a single message separated with newlines.
  + Advantage: Allows more messages to escape the 99 message limit
  + Advantage: Reduces the number of used commands in an action
  + Disadvantage: May increase total byte size of messages list.
  + Disadvantage: May increase the total number of messages, possibly hitting the 218 limit of some terps quicker.
2. Move "print" command codes to "odd" command slots (1 and 3) if possible.
3. Make sure that messages used by print command codes in "even" command slots are placed at the beginning of the messages list.
