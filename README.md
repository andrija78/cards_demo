# cards_demo

Public repo to give few answers for 
https://stackoverflow.com/questions/70149837/suggestion-to-build-a-multiplayer-texas-holdem-poker-game-using-nodejs-flutter


## The objective

Play Card events will happen in a quick succession. For exmple: we may chose to animate a card being played for 2 seconds, and other players might play cards every 1 second. In this case - we want to avoid multiple cards being animated at the same time. 
We also want to animate cards being collected once all players play their card.
Additionally - we may want to show additional messages (Popup, alerts, scoreboard) between cards being played.

So you want to have:
- We play the card
- Player 2 playes the card
- Player 3 plays the card
- We have a pop-up notification that player 3 called the game. We need to dismiss the notification
- Player 4 plays his card
- Player 3 collects all 4 cards
- Since this was the last round, we should the current scoreboard. We need to dismiss the scoreboard manuall
- New round starts, Player 3 plays the card
- ...

If we play against the AI - all the events could complete in milliseconds, yet we still want to animate them one by one.


## Inbound queue

So we will make this generic. We will create the inbound StreamQueue, and we will pass a generic TwoCompleter object:

```
final inboundController = StreamController<TwoCompleters>();
late StreamQueue<TwoCompleters> inboundQueue;
```

```
class TwoCompleters {
  Completer start = Completer();
  Completer end = Completer();
  Duration? watchDogDuration;

  TwoCompleters();

  TwoCompleters.withWatchDog(Duration watchDog) {
    start.future.then((value) => Future.delayed(watchDog).then((value) {
          if (!end.isCompleted) end.complete();
        }));
  }
}
```

TwoCompleters class is nothing more than a tuple with Two Completer objects. I didn't want to add a dependency on another package, so I used the simple implementation here. There is an added optional feature of a watch dog timer.

Here's how this works:

```
  PokerProvider() : model = PokerModel() {
    inboundQueue = StreamQueue<TwoCompleters>(inboundController.stream);
    inboundQueue.next.then((twoCompleters) => processQ(twoCompleters));
  }

  void processQ(TwoCompleters twoCompleters) {
    twoCompleters.start.complete();
    twoCompleters.end.future.then((_) => inboundQueue.next.then((twoCompleters) => processQ(twoCompleters)));
  }
```

StreamQueue is (according to the doc): 
> An asynchronous pull-based interface for accessing stream events. Wraps a stream and makes individual events available on request.

In PokerProvider constructor we immediately subscribe to the next object in the StreamQueue, and we call processQ function. The function will:
- Complete the start completer. This will enable the actual event processing to happen (more on that a bit later)
- Wait until the end completer is completed, and only then subscribe to the next event in the queue, repating the same process.


And here's the bit that will actually process the animation:

```
    void playCard(
      {required GameCard card,
      required GlobalKey sourceKey,
      required GlobalKey targetKey,
      required int playerId}) async {
    
        var twoCompleters = TwoCompleters();
        inboundController.sink.add(twoCompleters);
        var start = twoCompleters.start.future;

        await start;

        // Do the animation stuff here

        twoCompleters.end.complete();
    }

```

Once we receive the playCard event (from the current player, or from network), we create an instance of TWoCompleteds object, and push it to the Inbound Queue. And then we simply wait for start to complete. It will complete only once our event is out of the queue and ready to animate.
Once we are done with the animation, we complete 'end' completer. This will trigger the processQ to consume the next message....

And this is how we ensured that only a single event is being consumed from the queue.

## Basic Animation stuff

Now to the actual animation. So far we are able to enqueue play card events, but we also need to add additonal events - collect card, show message etc. 
This could (or should) work using the same approach - use the StreamQueue. In the current implementation, we are just using bunch of Completer objects to achieve the same. If I find time, I'll try to make this even more usable.

The basic animation works using the Overlay. I'll just explain main bits of code; there is a lot more going on to schedule various WidgetBinding events, which I hope I'll explain later in this document.

From the doc:

> Overlays let independent child widgets "float" visual elements on top of other widgets by inserting them into the overlay's stack. The overlay lets each of these widgets manage their participation in the overlay using OverlayEntry objects.

You could try do it without the overlay, but you will find that when moving card around, you need to deal with z-axis, and card goes under other cards which is what you don't expect...

This is how your FloatingActionButton works - it is rendered on a layer above your applicatoin layer.

To animate we need: Card being played, source and target position on screen, and player Id.

Animating a simple card throw will have several steps:
1. Find the exact on-screen location of the card being played. In Flutter, Rect object is what we are looking for
2. Find the Rect of the destination location - where your animation needs to end
3. Drow the same card on the same location in the Overlay layer. At this moment, both cards are painted, one on top the other.
4. Hide the original card - once the Overlay card starts movnig you want this hidden.
5. Animate the card. I simply use AnimatedPositioned.fromRect
6. Wait for the animation to finish. Conviniently, AnimatedPositioned has onEnd callback.
7. Once the animation is completed, your game state should reflect the new state - card is actually where it is supposed to be - on the table, drawn underneath the Overlay card.
8. Remove the overlay card.

Let's break it down:

### (1., 2.) Find the exact on-screen location
To do this, you will need a GlobalKey of the Widget you want to find.

First, we pre-define all the GlobalKeys we will need: 
- 4 player keys: when we collect the cards, this is where the animation goes. Also, for other players, this is where the played card will start from.
- 4 table keys: for 4 slots on the table
- 13 card keys: this is for our 13 cards we are showing.

```
class AnimationProvider extends ChangeNotifier {
  // This one will keep player's position to collect the card
  final keyPlayer = List<GlobalKey>.generate(4, (index) => GlobalKey(debugLabel: "keyPlayer[$index]"));

  // keys for 4 table cards and 13 player cards
  final keyTable = List<GlobalKey>.generate(4, (index) => GlobalKey(debugLabel: "keyTable[$index]"));
  final keyCard = List<GlobalKey>.generate(13, (index) => GlobalKey(debugLabel: "keyCard[$index]"));

  var mainVisible = <GlobalKey, bool>{};
  var overlayVisible = <GlobalKey, bool>{};

  BuildContext context;

  AnimationProvider(Stream<AnimationNotifierEvent> sourceStream, this.context) {
    for (var key in [...keyPlayer, ...keyTable, ...keyCard]) {
      mainVisible[key] = true;
      overlayVisible[key] = false;
    }
    subscription = sourceStream.listen((event) => add(event));

    Provider.of<PokerProvider>(context, listen: false).animationProvider = this;
  }

  // ...
}
```

You can also notice that we populate two lists: mainVisible and overlayVisible - this will come in handy later when we toggle visibility in each layer.

When drawing a Widget, we just need to pickup the key, and assign it. This is for the table:

```
    child: PokerCard(card: model.table[index], key: animationProvider.keyTable[index]))),
    
```

And finally - this is the function that will get you the Rect object for a given global key:

```
Rect getRectFromKey(GlobalKey key) {
    RenderBox renderBox = (key.currentContext!.findRenderObject())! as RenderBox;
    var targetPosition = renderBox.localToGlobal(Offset.zero);
    var targetSize = renderBox.size;
    // A Rect can be created with one its constructors or from an Offset and a Size using the & operator:
    Rect rect = targetPosition & targetSize;
    return rect;
}
```


## (3,4,5) Draw the card in the Overlay Layer, and animate it

This is how:

```
      Rect targetRect = getRectFromKey(animationSetup.targetKey!);
      Rect sourceRect = getRectFromKey(animationSetup.sourceKey!);

      var e = OverlayEntry(builder: (context) {
        return AnimatedPositioned.fromRect(
            rect: overlayVisible[animationSetup.sourceKey]! ? targetRect : sourceRect,
            child: PokerBasicCard(
              card: animationSetup.card!,
              isVisible: overlayVisible[animationSetup.sourceKey]!,
            ),
            duration: const Duration(seconds: 1),
            curve: Curves.bounceOut,
            onEnd: () {
              if (!animationSetup.completer.isCompleted) {
                animationSetup.completer.complete();
              }
            });
      });
      overlayEntries.add(e);
      Overlay.of(context)!.insert(e);
```

Notice few things:
- initially, overlayVisible is set to false, and mainVisible is set to true
- we will initially assig sourceRect as rect value to AnimatedPositioned - initially we want it rendered on the starting positioned. Later we will flip the visibility of main and overlay.
- PokerBasicCard is initially invisible.
- We define duration 1 second, and we define the curve.
- And we also define onEnd - remember - we need to send message back to queue handling that we are done


And this is how we trigger the animation to start: immediately after the code that added the Overlay, we schedule the change:

```
WidgetsBinding.instance!.addPostFrameCallback((_) async {
      
      overlayVisible[animationSetup.sourceKey!] = true;
      mainVisible[animationSetup.sourceKey!] = false;
      for (var e in overlayEntries) {
        e.markNeedsBuild();
      }
      notifyListeners();
    });
```

So now we flipped the visibility - in the same Screen rebuild, we made the main card invisible, and the Overlay Card visible.
Since the rect is defined through the same param ```(rect: overlayVisible[animationSetup.sourceKey]! ? targetRect : sourceRect,)``` - AnimatedPositioned will notice the location change and begin to animate it.


## 6 - Wait for animation to finish

This is where we use TwoCompleters.end - remember, the next card in the queue will wait until we complete this one. This is what we do in the onEnd callback from AnimatedPositioned:

```
onEnd: () {
  if (!animationSetup.completer.isCompleted) {
    animationSetup.completer.complete();
  }
})
```


## 7, 8 - Update the game state and remove the OverlayCard

Now this is where it becomes a bit tricky. When you play the card, you have this:
- Game state 1: The card is in your hand
- You play the card; this immediately crates Game state 2: the card is on the table
- But, we cannot allow the card to be shown on the table until our move animation completed. This is why we wait for the game state to refresh.
- Additionally - we want to remove the Overlay Card (the one we animated) only when the Game State 2 is applied. Otherwise we will have few frames with no card on the table.


We do this simply by creating another Completer.

In the backend.dart, this is how we pushed the animation event to animation.dart:

```
animationStreamCtrl.sink.add(AnimationNotifierEvent(
          completer: completer,
          nextGroupCompleter: nextGroupStart,
          previousGroupCompleter: previousGroup,
          cleanupCompleter: cleanup,
          type: 'collectCards',
          winningPlayer: winningPlayerId,
          numberOfPlayers: nextModel.numberOfPlayers,
          cards: List<GameCard>.generate(
          nextModel.numberOfPlayers, (player) => player == playerId ? card : nextModel.table[player]!)));
```

The completers are:
- completer: this is the main one; once this is completed, the next card move will be processed out of the queue
- nextGroupCompleter: once this is completer, the animation will remove it's OverLayEntires and mark the GlobalKey as invisible
- previousGroupCompleter: this is actually the nextGroupCompleter from the previous animation. Uhh, I'll need to draw few diagrams to explain....
- cleanupCompleter: this is the final completer. Once it completes, everything should be back to normal (Overlays are removed, all GlobalKeys have their default visibility values etc.)


Well, at least now I have a good idea how to re-write this code (first time I looked at it after making it work)...