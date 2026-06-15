import 'package:flutter/material.dart';
Future<void> save(BuildContext context) async {
  await Future.delayed(Duration(seconds: 1));
  Navigator.of(context).pop();   // cat#5: BuildContext used across an async gap, no mounted check
}
