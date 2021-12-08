import 'dart:async';
import 'package:cards_demo/backend.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'card.dart';

class AnimationNotifierEvent {
  Completer completer;

  final GameCard? card;
  GlobalKey? sourceKey;
  GlobalKey? targetKey;
  //final int targetPlayer;
  final Completer? cleanupCompleter;
  final Completer? nextGroupCompleter;
  final Completer? previousGroupCompleter;

  final String? type;
  final int? playerId;
  final int numberOfPlayers;
  final List<GameCard>? cards;
  final int? winningPlayer;

  AnimationNotifierEvent(
      {this.card,
      this.sourceKey,
      this.targetKey,
      required this.completer,
      this.cleanupCompleter,
      this.nextGroupCompleter,
      this.previousGroupCompleter,
      this.type,
      this.playerId,
      this.numberOfPlayers = 4,
      this.cards,
      this.winningPlayer});
}

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

  late StreamSubscription subscription;
  bool active = false;
  Completer? completer;

  var animationSetupList = <AnimationNotifierEvent>[];

  void add(AnimationNotifierEvent event) {
    if (event.type == 'playCard') {
      event.sourceKey ??= keyPlayer[event.playerId!];
      event.targetKey ??= keyTable[event.playerId!];
      animationSetupList = [event];
    }

    if (event.type == 'collectCards') {
      var completers = List<Completer>.generate(event.numberOfPlayers, (player) => Completer());

      animationSetupList = List<AnimationNotifierEvent>.generate(
          event.numberOfPlayers,
          (player) => AnimationNotifierEvent(
                card: event.cards![player],
                sourceKey: keyTable[player],
                targetKey: keyPlayer[event.winningPlayer!],
                completer: completers[player],
                cleanupCompleter: event.cleanupCompleter,
                nextGroupCompleter: event.nextGroupCompleter,
                previousGroupCompleter: event.previousGroupCompleter,
              ));

      Future.wait(completers.map((e) => e.future)).then((value) => event.completer.complete());
    }
    active = true;
    completer = event.completer;
    completer!.future.then((value) => active = false);
    notifyListeners();
  }

  //to be called from wdget during build (after it is notified)
  //we can get context from the key - this would remove a need for argument,
  //and probbably enable us to call it from backend directly
  void runAnimation(BuildContext context) {
    if (animationSetupList.isEmpty) return;

    // we need local copy!!!!
    var localSetupList = animationSetupList.toList();

    Completer nextGroupCompleter = localSetupList[0].nextGroupCompleter!;
    Completer cleanupCompleter = localSetupList[0].cleanupCompleter!;
    var overlayEntries = <OverlayEntry>[];

    //setup the animation
    for (var animationSetup in localSetupList) {
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
    }

    // start the animation
    WidgetsBinding.instance!.addPostFrameCallback((_) async {
      for (var animationSetup in localSetupList) {
        overlayVisible[animationSetup.sourceKey!] = true;
        mainVisible[animationSetup.sourceKey!] = false;
        if (animationSetup.previousGroupCompleter != null && (!animationSetup.previousGroupCompleter!.isCompleted)) {
          animationSetup.previousGroupCompleter!.complete();
        }
      }
      for (var e in overlayEntries) {
        e.markNeedsBuild();
      }
      notifyListeners();
    });

    nextGroupCompleter.future.then((value) {
      for (var animationSetup in localSetupList) {
        overlayVisible[animationSetup.sourceKey!] = false;
      }
      for (var e in overlayEntries) {
        e.remove();
      }
      notifyListeners();
    });

    cleanupCompleter.future.then((value) {
      //if (!nextGroupCompleter.isCompleted) nextGroupCompleter.complete();
      for (var animationSetup in localSetupList) {
        mainVisible[animationSetup.sourceKey!] = true;
      }
      notifyListeners();
    });
  }

  Rect getRectFromKey(GlobalKey key) {
    RenderBox renderBox = (key.currentContext!.findRenderObject())! as RenderBox;
    var targetPosition = renderBox.localToGlobal(Offset.zero);
    var targetSize = renderBox.size;
    // A Rect can be created with one its constructors or from an Offset and a Size using the & operator:
    Rect rect = targetPosition & targetSize;
    return rect;
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }
}
