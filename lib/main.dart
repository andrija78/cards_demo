import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'backend.dart';
import 'table.dart';
import 'animation.dart';

void main() {
  runApp(MultiProvider(providers: [
    ChangeNotifierProvider(create: (context) => PokerProvider()),
    ChangeNotifierProvider(
        create: (context) =>
            AnimationProvider(Provider.of<PokerProvider>(context, listen: false).animationStream, context),
        lazy: false),
    ChangeNotifierProvider(
        create: (context) => DialogNotifier(Provider.of<PokerProvider>(context, listen: false).dialogStream),
        lazy: false),
    ChangeNotifierProvider(
        create: (context) => NavigationNotifier(Provider.of<PokerProvider>(context, listen: false).navigationStream),
        lazy: false),
    ChangeNotifierProvider(
        create: (context) => ModelNotifier(Provider.of<PokerProvider>(context, listen: false).modelStream),
        lazy: false),
    ChangeNotifierProvider(
        create: (context) => SnackBarNotifier(Provider.of<PokerProvider>(context, listen: false).snackStream),
        lazy: false),
  ], child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Poker Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const PokerTable(title: 'Poker Demo'),
    );
  }
}
