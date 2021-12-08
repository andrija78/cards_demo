import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'animation.dart';

enum Suite { clubs, diamonds, hearts, spades }

enum Value { v2, v3, v4, v5, v6, v7, v8, v9, v10, jack, queen, king, ace }

class GameCard {
  final Suite suite;
  final Value value;

  String get suiteString => suite.toString().split('.').last;
  String get valueString => value.toString().split('.').last.replaceAll("v", "");
  String get assetName {
    String assetName = valueString + "_of_" + suiteString + ".png";
    return assetName;
  }

  const GameCard({required this.suite, required this.value});
}

class PokerBasicCard extends StatelessWidget {
  final bool isVisible;
  final GameCard? card;
  // final GlobalKey key;

  final String size;

  static const imageWidth = {'SMALL': 30.0 * 1.5, 'LARGE': 60.0};
  static const imageHeight = {'SMALL': 60.0 * 1.5, 'LARGE': 120.0};

  const PokerBasicCard({required this.card, this.isVisible = true, this.size = 'LARGE', Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    //in case card is null, we will render a random card (Ace of Hearts) and make it invisible
    //- so it will still take space on screen
    return Visibility(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: Image.asset('assets/${(card ?? const GameCard(suite: Suite.hearts, value: Value.ace)).assetName}',
            height: imageHeight[size], width: imageWidth[size]),
      ), //key),
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      visible: card == null ? false : isVisible,
    );
  }
}

class PokerCard extends StatelessWidget {
  final GameCard? card;
  final void Function()? onDoubleTap;
  final void Function()? onTap;
  final String size;

  const PokerCard({required this.card, this.onTap, this.onDoubleTap, this.size = 'LARGE', Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AnimationProvider>(builder: (context, animationProvider, child) {
      return GestureDetector(
          child: PokerBasicCard(
              card: card, isVisible: key != null ? animationProvider.mainVisible[key]! : true, size: size),
          onTap: onTap,
          onDoubleTap: onDoubleTap);
    });
  }
}

class Deck {
  late List<GameCard?> cards;
  Deck(this.cards);
  Deck.initDeck() {
    cards = <GameCard>[];
    for (var suite in Suite.values) {
      for (var value in Value.values) {
        cards.add(GameCard(value: value, suite: suite));
      }
    }
  }

  Deck.fromDeck(Deck deck) {
    cards = deck.cards.toList();
  }

  void shuffle() => cards.shuffle(Random());

  void sort() => cards.sort((a, b) {
        if (a == null) return -1;
        if (b == null) return 1;
        return a.suite != b.suite ? a.suite.index - b.suite.index : a.value.index - b.value.index;
      });
}
