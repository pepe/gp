# Examples

All the code in the examples is heavily commented.

## Counter

[REPL example](/~pepe/shawn/tree/master/item/examples/counter/init.janet)
from the main README in file.

The flow is the following:

* initialize Shawn with the counter set to zero
* confirm `inc-and-print`
  * increase counter with `IncreaseCounter`
  * print the counter with `PrintCounter`

You can run the code with:


```
janet examples/counter/init.janet
```

## Chains

[Chaining example](/~pepe/Shawn/tree/master/item/examples/chains/init.Janet)
of multistep processing of the files. There are several acts, which are chained
together.

The flow is the following:

* initialize Shawn with directory filename
* Get the names from the directory file with `ReadDirectory`
  * save the directory to the envelope with  `save-directory`
  * process directory with `ProcessDirectory`
    * get the user description from each user file with `get-user`
      * save the description to envelope with `save-user`
* print the users with descriptions with `PrintUsers`

You can run the code with:

```
janet examples/chains/init.janet
```

## Prompt

[The simulation](/~pepe/Shawn/tree/master/item/examples/prompt/)
of the control prompt for the TUI application. Commands are parsed from user
input with PEG and then confirmed by the Shawn.

The example is the biggest one of the three, so I divided the code into
three modules:

* `init.janet` an entry point of the application. In this code, we initialize the
  Shawn and set up observers. It contains the main parsed commands dispatch.
* `parser.janet` contains code for parsing user input with PEG.
* `acts.janet` is the file where the acts are defined.

### events

As said above, the file `acts.janet` contains act definitions. I have tried
to add all the combinations and styles that I am aware of now. Save the
function watchable due to the limitation of getline with the `ev` cooperation.

Highlights:
* `AddRandom` this act simulates computing in the classic fiber. It does not
  yield, as it has only one return target. This act is what I call static.
* `add-many-randoms` utility function for when you need to confirm more than one
  `AddRandom` act.
* `ThreadRandom` is an example of simple thread orchestration in the act. event
  spins up ten threads simulating resource-demanding computing. Again I consider
  this static act as it does not have parameters.
* `add-many-trandoms` is similar to `add-many-randoms` as a utility to create
  more than one static `ThreadRandom` act.
* `unknow-command` this is interesting because it is a dynamic act as it takes
  the wrong command argument, but it is also a combined act, as it contains both
  `:watch` and `:effect` methods.

The flow is most straightforward from all three examples:
* forever
  * read and parse user input
    * confirm right act matched from the parser output

You can run the code with:

```
janet examples/prompt/init.janet
```

The program will present you with a command prompt and type `h` for other
commands.

## Boxes

[This example](/~pepe/gp/tree/master/item/examples/coccons/) shows
how you can run RPC server as part of the Shawn Flow. Its `init.janet` contains
all the bits and pieces to construct the Shawn with the RPC server. The server
has three endpoints to increase a counter, print it and for server to finish.
The interesting thing here, is that we can access the envelope and through
emerging issuing the new events to confirm by Shawn.

In the `client.janet` file are defined simple clients that perform the
operations on the server. The two clients created both issue remote calls to the
server. And code prints the intermediate results.

For running this example you have run:

```
janet examples/cocoons/init.janet
```

on one terminal to initialize Shawn with server. And then run:

```
janet examples/cocoons/client.janet
```

To issue the remote calls and see the output.

