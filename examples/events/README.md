# Examples

All the code in the examples is heavily commented.

## Counter

[REPL example](/~pepe/gp/tree/master/item/examples/events/counter/init.janet)
from the main README in file.

The flow is the following:

* initialize manager with the counter set to zero
* confirm `inc-and-print`
  * increase counter with `IncreaseCounter`
  * print the counter with `PrintCounter`

You can run the code with:


```
janet examples/events/counter/init.janet
```

## Chains

[Chaining example](/~pepe/gp/tree/master/item/examples/events/chains/init.Janet)
of multistep processing of the files. There are several events, which are chained
together.

The flow is the following:

* initialize manager with directory filename
* Get the names from the directory file with `ReadDirectory`
  * save the directory to the state with  `save-directory`
  * process directory with `ProcessDirectory`
    * get the user description from each user file with `get-user`
      * save the description to state with `save-user`
* print the users with descriptions with `PrintUsers`

You can run the code with:

```
janet examples/events/chains/init.janet
```

## Prompt

[The simulation](/~pepe/gp/tree/master/item/examples/prompt/)
of the control prompt for the TUI application. Commands are parsed from user
input with PEG and then confirmed by the manager.

The example is the biggest one of the three, so I divided the code into
three modules:

* `init.janet` an entry point of the application. In this code, we initialize the
  manager and set up observers. It contains the main parsed commands dispatch.
* `parser.janet` contains code for parsing user input with PEG.
* `events.janet` is the file where the events are defined.

### events

As said above, the file `events.janet` contains events' definitions. I have tried
to add all the combinations and styles that I am aware of now. Save the
function watchable due to the limitation of getline with the `ev` cooperation.

Highlights:
* `AddRandom` this event simulates computing in the classic fiber. It does not
  yield, as it has only one return target. This event is what I call static.
* `add-many-randoms` utility function for when you need to confirm more than one
  `AddRandom` event.
* `ThreadRandom` is an example of simple thread orchestration in the event. event
  spins up ten threads simulating resource-demanding computing. Again I consider
  this static event as it does not have parameters.
* `add-many-trandoms` is similar to `add-many-randoms` as a utility to create
  more than one static `ThreadRandom` event.
* `unknow-command` this is interesting because it is a dynamic event as it takes
  the wrong command argument, but it is also a combined event, as it contains both
  `:watch` and `:effect` methods.

The flow is most straightforward from all three examples:
* forever
  * read and parse user input
    * confirm right event matched from the parser output

You can run the code with:

```
janet examples/events/prompt/init.janet
```

The program will present you with a command prompt and type `h` for other
commands.

