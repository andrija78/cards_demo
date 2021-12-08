import 'dart:async';
import 'dart:math';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'animation.dart';
import 'card.dart';

final _randomGen = Random();
int _random(int min, int max) => min + _randomGen.nextInt(max - min);

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

class PokerModel {
  var playerDecks = <Deck>[];
  var table = List<GameCard?>.filled(4, null);
  int currentPlayerId = 0;
  var playerNames = <String>["Player 0", "Player 1", "Player 2", "Player 3"];

  void dealShuffeledDeck(Deck deck) {
    for (int i = 0; i < 4; i++) {
      playerDecks.add(Deck(deck.cards.getRange(i * 13, (i + 1) * 13).toList())..sort());
    }
  }

  PokerModel() {
    var deck = Deck.initDeck()..shuffle();
    dealShuffeledDeck(deck);
  }

  PokerModel.fromPokerModel(PokerModel model) {
    for (var m in model.playerDecks) {
      playerDecks.add(Deck.fromDeck(m));
    }
    table = List<GameCard?>.from(model.table);
    currentPlayerId = model.currentPlayerId;
    playerNames = model.playerNames.toList();
  }

  void nextPlayer() {
    currentPlayerId++;
    if (currentPlayerId >= playerNames.length) currentPlayerId = 0;
  }

  int get numberOfPlayers => playerNames.length;

  bool get gameOver {
    for (var m in playerDecks) {
      if (m.cards.indexWhere((element) => element != null) != -1) return false;
    }
    return true;
  }
}

class PokerProvider extends ChangeNotifier {
  PokerModel model;

  late AnimationProvider animationProvider;

  final inboundController = StreamController<TwoCompleters>();
  late StreamQueue<TwoCompleters> inboundQueue;

  var completers = List<Completer?>.filled(4, null);
  Completer? dialogCompleter;

  final animationStreamCtrl = StreamController<AnimationNotifierEvent>();
  Stream<AnimationNotifierEvent> get animationStream => animationStreamCtrl.stream;

  final dialogStreamCtrl = StreamController<DialogNotifierEvent>();
  Stream<DialogNotifierEvent> get dialogStream => dialogStreamCtrl.stream;

  final navigationStreamCtrl = StreamController<StringNotifierEvent>();
  Stream<StringNotifierEvent> get navigationStream => navigationStreamCtrl.stream;

  final modelStreamCtrl = StreamController<ModelNotifierEvent>();
  Stream<ModelNotifierEvent> get modelStream => modelStreamCtrl.stream;

  final snackStreamCtrl = StreamController<StringNotifierEvent>();
  Stream<StringNotifierEvent> get snackStream => snackStreamCtrl.stream;

  PokerProvider() : model = PokerModel() {
    inboundQueue = StreamQueue<TwoCompleters>(inboundController.stream);
    inboundQueue.next.then((twoCompleters) => processQ(twoCompleters));
  }

  void processQ(TwoCompleters twoCompleters) {
    twoCompleters.start.complete();
    twoCompleters.end.future.then((_) => inboundQueue.next.then((twoCompleters) => processQ(twoCompleters)));
  }

  Future<void> _showSnackBar(String text) async {
    var completer = Completer();
    snackStreamCtrl.sink.add(StringNotifierEvent(completer: completer, text: text));
    await completer.future;
  }

  Future<void> _showDialog(String dialogText) async {
    var completer = Completer();
    dialogStreamCtrl.sink.add(DialogNotifierEvent(completer: completer, dialogText: dialogText));
    await completer.future;
  }

  void playCard(
      {required GameCard card,
      required GlobalKey sourceKey,
      required GlobalKey targetKey,
      required int playerId}) async {
    var twoCompleters = TwoCompleters();
    inboundController.sink.add(twoCompleters);
    var start = twoCompleters.start.future;

    await start;

    var cleanup = Completer();
    var nextGroupStart = Completer();
    var completer = Completer();

    animationStreamCtrl.sink.add(AnimationNotifierEvent(
        completer: completer,
        nextGroupCompleter: nextGroupStart,
        cleanupCompleter: cleanup,
        type: 'playCard',
        card: card,
        playerId: playerId,
        sourceKey: playerId == 0 ? sourceKey : null,
        targetKey: targetKey));

    if (model.currentPlayerId != playerId) {
      await completer.future;

      await _showSnackBar('Not your turn to play!!!');
      nextGroupStart.complete();

      cleanup.complete();
      twoCompleters.end.complete();
      return;
    }
    await completer.future;

    var nextModel = PokerModel.fromPokerModel(model);
    var winningPlayerId = _updateModel(card: card, playerId: playerId, type: 'playCard', model: nextModel);

    if (winningPlayerId != -1) {
      var completer = Completer();
      var previousGroup = nextGroupStart;
      nextGroupStart = Completer();

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

      await completer.future;
      //empty the table
      nextModel.table = List<GameCard?>.filled(4, null);
      nextModel.currentPlayerId = winningPlayerId;
    }

    model = nextModel;
    await _refreshModel(model);

    nextGroupStart.complete();
    cleanup.complete();

    twoCompleters.end.complete();

    if (card.suite == Suite.clubs && card.value == Value.ace) {
      await _showDialog("Player $playerId played Ace of Clubs!");
    }

    if (model.gameOver) {
      await _showDialog("Game Over!");
      return;
    }

    if (model.currentPlayerId != 0) {
      playCard(
          card: model.playerDecks[model.currentPlayerId].cards.firstWhere((element) => element != null)!,
          sourceKey: animationProvider.keyPlayer[model.currentPlayerId],
          targetKey: animationProvider.keyTable[model.currentPlayerId],
          playerId: model.currentPlayerId);
    }
  }

  int _updateModel({required GameCard card, required int playerId, required String type, required PokerModel model}) {
    if (type == 'playCard') {
      var index = model.playerDecks[playerId].cards
          .indexWhere((element) => element != null && element.suite == card.suite && element.value == card.value);
      model.playerDecks[playerId].cards[index] = null;
      model.table[playerId] = card;
      model.nextPlayer();
    }

    // if 4 cards are played, return the winning player
    if (model.table.where((element) => element != null).length == model.numberOfPlayers) {
      return _random(0, 3);
    } else {
      return -1;
    }
  }

  Future<void> _refreshModel(PokerModel model) async {
    var completer = Completer();

    var message = ModelNotifierEvent(completer: completer, model: model);

    modelStreamCtrl.sink.add(message);
    await completer.future;
  }

  @override
  void dispose() {
    super.dispose();
    inboundController.close();
    animationStreamCtrl.close();
  }
}

class ModelNotifierEvent extends MyNotifierEvent {
  PokerModel model;

  ModelNotifierEvent({required this.model, required Completer completer}) : super(completer: completer);
}

class ModelNotifier extends MyNotifier {
  var subscriptionCompleter = Completer();
  get subscriptionFuture => subscriptionCompleter.future;
  ModelNotifier(Stream<ModelNotifierEvent> sourceStream) : super(sourceStream);

  late PokerModel model;

  @override
  void add(covariant ModelNotifierEvent event) async {
    model = event.model;
    super.add(event);
    event.completer.complete();
    if (!subscriptionCompleter.isCompleted) subscriptionCompleter.complete();
  }
}

class MyNotifierEvent {
  Completer completer;

  @mustCallSuper
  MyNotifierEvent({required this.completer});
}

class MyNotifier extends ChangeNotifier {
  late StreamSubscription subscription;
  bool active = false;
  Completer? completer;

  MyNotifier(Stream<MyNotifierEvent> sourceStream) {
    subscription = sourceStream.listen((event) => add(event));
  }

  @mustCallSuper
  void add(MyNotifierEvent event) {
    active = true;
    event.completer.future.then((value) => active = false);
    completer = event.completer;
    notifyListeners();
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }
}

class DialogNotifierEvent extends MyNotifierEvent {
  String dialogText;

  DialogNotifierEvent({required this.dialogText, required Completer completer}) : super(completer: completer);
}

class DialogNotifier extends MyNotifier {
  late String dialogText;

  DialogNotifier(Stream<DialogNotifierEvent> sourceStream) : super(sourceStream);

  @override
  void add(covariant DialogNotifierEvent event) {
    dialogText = event.dialogText;
    super.add(event);
  }
}

class StringNotifierEvent extends MyNotifierEvent {
  String text;

  StringNotifierEvent({required this.text, required Completer completer}) : super(completer: completer);
}

class SnackBarNotifier extends MyNotifier {
  late String text;
  SnackBarNotifier(Stream<StringNotifierEvent> sourceStream) : super(sourceStream);

  @override
  void add(covariant StringNotifierEvent event) {
    text = event.text;
    super.add(event);
  }
}

class NavigationNotifier extends MyNotifier {
  late String route;

  NavigationNotifier(Stream<StringNotifierEvent> sourceStream) : super(sourceStream);

  @override
  void add(covariant StringNotifierEvent event) {
    route = event.text;
    super.add(event);
  }
}
