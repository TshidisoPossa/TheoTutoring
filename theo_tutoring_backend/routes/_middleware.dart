import 'package:dart_frog/dart_frog.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:theo_tutoring_backend/database.dart';

// Lets the Flutter web app (served from another localhost port) call the API.
const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
};

Handler middleware(Handler handler) {
  return (context) async {
    // Browsers send an OPTIONS "preflight" before a POST with an auth header.
    if (context.request.method == HttpMethod.options) {
      return Response(statusCode: 204, headers: _corsHeaders);
    }

    final conn = await getConnection();
    final response = await handler
        .use(provider<MySQLConnection>((_) => conn))
        .call(context);
    return response.copyWith(headers: {...response.headers, ..._corsHeaders});
  };
}
