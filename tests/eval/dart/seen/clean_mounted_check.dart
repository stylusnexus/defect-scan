import 'package:flutter/material.dart';
class S extends State {
  Future<void> save(BuildContext context) async {
    await Future.delayed(Duration(seconds: 1));
    if (!mounted) return;            // NEAR-MISS: looks like the async-gap bug, but guards with mounted
    Navigator.of(context).pop();
  }
}
