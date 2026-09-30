import 'package:flutter/material.dart';
import 'login_page.dart';
import 'student_registration.dart';
import 'tutor_registrationPage1.dart'; //Tutor reg page

class RoleSelectionPage extends StatefulWidget {
  const RoleSelectionPage({super.key});

  @override
  State<RoleSelectionPage> createState() => _RoleSelectionPageState();
}

class _RoleSelectionPageState extends State<RoleSelectionPage> {
  String selectedRole = 'student';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 30),

              // TheoTutoring logo and mascot placeholder
              CircleAvatar(
                radius: 45,
                backgroundColor: Colors.blue.shade100,
                child: const Icon(Icons.school, size: 50, color: Colors.blue),
              ),

              const SizedBox(height: 15),

              const Text(
                'TheoTutoring',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 50),

              const Text(
                'How will you use the app?',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 30),
              // Student option
              GestureDetector(
                onTap: () {
                  setState(() {
                    selectedRole = 'student';
                  });
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: selectedRole == 'student'
                        ? Colors.blue.shade50
                        : Colors.white,
                    border: Border.all(
                      color: selectedRole == 'student'
                          ? Colors.blue
                          : Colors.grey.shade300,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.school, color: Colors.blue, size: 35),
                      SizedBox(height: 10),
                      Text(
                        "I'm a student",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'I want to find a tutor and learn new skills.',
                        style: TextStyle(fontSize: 15, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Tutor option
              GestureDetector(
                onTap: () {
                  setState(() {
                    selectedRole = 'tutor';
                  });
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: selectedRole == 'tutor'
                        ? Colors.blue.shade50
                        : Colors.white,
                    border: Border.all(
                      color: selectedRole == 'tutor'
                          ? Colors.blue
                          : Colors.grey.shade300,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.person, color: Colors.blue, size: 35),
                      SizedBox(height: 10),
                      Text(
                        "I'm a tutor",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'I want to share my knowledge and earn money.',
                        style: TextStyle(fontSize: 15, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: () {
                    if (selectedRole == 'student') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const StudentRegistrationPage(),
                        ),
                      );
                    } else if (selectedRole == 'tutor') //If the user selects tutor it will redirect them to the Tutor Reg.
                    {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const TutorRegistrationPage1(),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const SizedBox(height: 15),

Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    const Text(
      'Already have an account? ',
      style: TextStyle(
        fontSize: 14,
      ),
    ),
    TextButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const LoginPage(),
          ),
        );
      },
      child: const Text(
        'Log in',
        style: TextStyle(
          color: Colors.blue,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    ),
  ],
),
            ],
          ),
        ),
      ),
    );
  }
}
