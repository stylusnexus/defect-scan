import 'package:flutter/material.dart';
class S extends State {
  final c = TextEditingController();   // cat#4: controller never disposed in dispose()
  Widget build(BuildContext context) => TextField(controller: c);
}
