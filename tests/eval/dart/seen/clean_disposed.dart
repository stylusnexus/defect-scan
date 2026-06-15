import 'package:flutter/material.dart';
class S extends State {
  final c = TextEditingController();
  void dispose() { c.dispose(); super.dispose(); }   // correct: disposed
  Widget build(BuildContext context) => TextField(controller: c);
}
