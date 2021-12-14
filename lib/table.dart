import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'animation.dart';
import 'backend.dart';
import 'card.dart';

class PokerTable extends StatefulWidget {
  const PokerTable({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  _PokerTableState createState() => _PokerTableState();
}

class _PokerTableState extends State<PokerTable> {
  Future<void> _showDialog(BuildContext context, String dialogText) async {
    await showDialog(
        context: context,
        builder: (BuildContext context) {
          return SimpleDialog(title: Text(dialogText), children: <Widget>[
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ]);
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
        ),
        body: Consumer<DialogNotifier>(
            builder: (context, value, child) {
              if (value.active) {
                WidgetsBinding.instance?.addPostFrameCallback((_) async {
                  await _showDialog(context, value.dialogText);
                  if (!value.completer!.isCompleted) value.completer!.complete();
                });
              }
              return child!;
            },
            child: Consumer<SnackBarNotifier>(
                builder: (context, value, child) {
                  if (value.active) {
                    WidgetsBinding.instance?.addPostFrameCallback((_) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(value.text),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Colors.redAccent,
                        action: SnackBarAction(
                          label: 'Ok',
                          onPressed: () {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          },
                        ),
                      ));

                      if (!value.completer!.isCompleted) value.completer!.complete();
                    });
                  }
                  return child!;
                },
                child: Consumer<NavigationNotifier>(builder: (context, value, child) {
                  if (value.active) {
                    WidgetsBinding.instance?.addPostFrameCallback((_) async {
                      await Navigator.pushNamed(context, value.route);
                      if (!value.completer!.isCompleted) value.completer!.complete();
                    });
                  }
                  return child!;
                }, child: Consumer2<PokerProvider, AnimationProvider>(
                  builder: (context, poker, animationProvider, child) {
                    if (animationProvider.active) {
                      animationProvider.active = false;
                      WidgetsBinding.instance!.addPostFrameCallback((_) async {
                        animationProvider.runAnimation(context);
                      });
                    }
                    var model = poker.model;
                    return AbsorbPointer(
                      child: Column(children: <Widget>[
                        Flexible(flex: 1, child: _buildOtherPlayer(model, 2, animationProvider.keyPlayer[2])),
                        Flexible(
                            flex: 6,
                            child: Row(
                              children: <Widget>[
                                _buildOtherPlayer(model, 1, animationProvider.keyPlayer[1]),
                                Flexible(flex: 5, child: _buildCenter(model, animationProvider)),
                                _buildOtherPlayer(model, 3, animationProvider.keyPlayer[3]),
                              ],
                            )),
                        Flexible(flex: 4, child: _buildBottom(model, animationProvider, poker))
                      ]),
                      absorbing: false, //showingPreviousHand,
                    );
                  },
                )))));
  }

  Widget _buildOtherPlayer(PokerModel model, index, key) {
    return Container(
        key: key,
        color: Colors.lightBlue,
        padding: const EdgeInsets.all(5.0),
        alignment: Alignment.center,
        child: Stack(
          children: <Widget>[
            Align(
              alignment: Alignment.center,
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Icon(Icons.person, color: model.currentPlayerId == index ? Colors.red : Colors.black),
                Text(model.playerNames.elementAt(index))
              ]),
            ),
          ],
        ));
  }

  Widget _buildCenter(PokerModel model, AnimationProvider animationProvider) {
    return Container(
      color: Colors.green,
      padding: const EdgeInsets.all(20.0),
      alignment: Alignment.center,
      child: Stack(
        children: List<Widget>.generate(
            model.playerNames.length,
            (index) => Align(
                alignment: [Alignment.bottomCenter, Alignment.centerLeft, Alignment.topCenter, Alignment.centerRight]
                    .elementAt(index),
                child: PokerCard(card: model.table[index], key: animationProvider.keyTable[index]))),
      ),
    );
  }

  Widget _buildBottom(PokerModel model, AnimationProvider animationProvider, PokerProvider poker) {
    var cards = model.playerDecks[0].cards;
    // 7 cards in first row, 6 cards in second row
    var rowCards = [7, 6];

    return Container(
        color: Colors.green,
        child: Column(
          children: <Widget>[
            for (var row = 0; row <= 1; row++)
              Flexible(
                  flex: 1,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: cards
                          .skip(row == 1 ? rowCards[0] : 0)
                          .take(rowCards[row])
                          .toList()
                          .asMap()
                          .map<dynamic, Widget>((index, card) => MapEntry(
                              index,
                              Container(
                                  // we select middle card of the top row - this is where collected cards will animate to
                                  key: row == 0 && index == 3 ? animationProvider.keyPlayer[0] : null,
                                  color: Colors.green,
                                  padding: const EdgeInsets.all(5.0),
                                  alignment: Alignment.center,
                                  child: PokerCard(
                                      key: animationProvider.keyCard[index + (row == 1 ? rowCards[0] : 0)],
                                      card: card,
                                      size: 'SMALL',
                                      onTap: () => poker.playCard(
                                          playerId: 0,
                                          card: card!,
                                          sourceKey: animationProvider.keyCard[index + (row == 1 ? rowCards[0] : 0)],
                                          targetKey: animationProvider.keyTable[0])))))
                          .values
                          .toList()))
          ],
        ));
  }
}
