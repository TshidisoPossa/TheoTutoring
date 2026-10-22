import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'student_chat_models.dart';

class StudentChatService {
  static const String _baseUrl = 'http://localhost:8080';

  Future<List<StudentChatContact>> getConversations() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final response = await http
        .get(
          Uri.parse('$_baseUrl/student/conversations'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(
        'Loading conversations failed: '
        '${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map(
          (item) => StudentChatContact.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList();
  }
}
