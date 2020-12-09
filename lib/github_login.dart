import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:url_launcher/url_launcher.dart';

final _authorizationEndpoint =
    Uri.parse('https://github.com/login/oauth/authorize');
final _tokenEndpoint = Uri.parse('https://github.com/login/oauth/access_token');

class GithubLoginWidget extends StatefulWidget {
  const GithubLoginWidget(
      {@required this.builder,
      @required this.githubClientId,
      @required this.githubClientSecret,
      @required this.githubScopes});

  final AuthenticatedBuilder builder;
  final String githubClientId;
  final String githubClientSecret;
  final List<String> githubScopes;
  @override
  _GithubLoginWidgetState createState() => _GithubLoginWidgetState();
}

typedef AuthenticatedBuilder = Widget Function(
    BuildContext context, oauth2.Client client);

class _GithubLoginWidgetState extends State<GithubLoginWidget> {
  HttpServer _redirectServer;
  oauth2.Client _client;

  @override
  Widget build(BuildContext context) {
    if (_client != null) {
      return widget.builder(context, _client);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("GitHud Login"),
      ),
      body: Center(
        child: RaisedButton(
          onPressed: () async {
            await _redirectServer?.close();
            _redirectServer = await HttpServer.bind('localhost', 0);
            var authenticatedHttpClient = await _getOAuth2Client(
                Uri.parse('http://localhost:${_redirectServer.port}/auth'));
            setState(() {
              _client = authenticatedHttpClient;
            });
          },
          child: const Text("Login to GitHub"),
        ),
      ),
    );
  }

  Future<oauth2.Client> _getOAuth2Client(Uri redirectUrl) async {
    if (widget.githubClientId.isEmpty || widget.githubClientSecret.isEmpty) {
      throw const GithubLoginException(
          'githubClientId and githubClientSecret must be not empty. ' +
              'See `lib/github_oauth_credentials.dart` for more detail.');
    }

    var grant = oauth2.AuthorizationCodeGrant(
      widget.githubClientId,
      _authorizationEndpoint,
      _tokenEndpoint,
      secret: widget.githubClientSecret,
      httpClient: _JsonAcceptingHttpClient(),
    );

    var authorizationUrl =
        grant.getAuthorizationUrl(redirectUrl, scopes: widget.githubScopes);
    await _redirect(authorizationUrl);
    var responseQueryParameters = await _listen();
    var client =
        await grant.handleAuthorizationResponse(responseQueryParameters);

    return client;
  }

  Future<void> _redirect(Uri authorizationUrl) async {
    var url = authorizationUrl.toString();
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw GithubLoginException('Could not launch $url');
    }
  }

  Future<Map<String, String>> _listen() async {
    var request = await _redirectServer.first;
    var params = request.uri.queryParameters;

    request.response.statusCode = 200;
    request.response.headers.set('content-type', 'text/plain');
    request.response.writeln('Authenticated ! You can close this tab.');
    await request.response.close();
    await _redirectServer.close();
    _redirectServer = null;
    return params;
  }
}

class _JsonAcceptingHttpClient extends http.BaseClient {
  final _httpClient = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Accept'] = 'application/json';
    return _httpClient.send(request);
  }
}

class GithubLoginException implements Exception {
  const GithubLoginException(this.message);
  final String message;
  @override
  String toString() => message;
}