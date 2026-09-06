import 'package:flutter/material.dart'; // This is to enable design widgets

//Defines a new widget call TutorRegister /
class TutorRegistration extends StatelessWidget {
  const TutorRegistration({super.key});

  //building the actual UI that gets drawn on screen
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      //Top nav Bar code
      appBar: AppBar(title: const Text('Welcome to TheoTutoring')),
    ); //This is to provide the basic page structure app bar + body
  }
}
