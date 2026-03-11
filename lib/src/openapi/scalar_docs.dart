/// Scalar API Reference handler — serves a single-page HTML widget.
///
/// The HTML loads `@scalar/api-reference` from a CDN and points it at the
/// local `/openapi.json` endpoint.  No server-side dependencies; no pub
/// package required.
///
/// Canonical HTML payload defined in PRD-002.
library;

import 'package:shelf/shelf.dart';

const _scalarHtmlTemplate = '''
<!DOCTYPE html>
<html>
  <head>
    <title>{{title}} — API Reference</title>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
  </head>
  <body>
    <script
      id="api-reference"
      data-url="/openapi.json"
      src="https://cdn.jsdelivr.net/npm/@scalar/api-reference">
    </script>
  </body>
</html>''';

/// Returns a Shelf [Handler] that serves the Scalar API Reference HTML.
///
/// ```dart
/// router.get('/docs', scalarDocsHandler(title: 'My API'));
/// ```
Handler scalarDocsHandler({required String title}) {
  final html = _scalarHtmlTemplate.replaceFirst('{{title}}', title);

  return (Request request) {
    return Response.ok(
      html,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  };
}
