/// Swagger UI docs handler — serves an HTML page with the Swagger UI widget.
///
/// Loads `swagger-ui-dist@5` from jsdelivr CDN and points it at the local
/// `/openapi.json` endpoint.  No server-side dependencies; no pub package
/// required.
///
/// Canonical HTML payload defined in PRD-003.
library;

import 'package:shelf/shelf.dart';

const _swaggerUiHtmlTemplate = '''
<!DOCTYPE html>
<html>
  <head>
    <title>{{title}} — API Reference</title>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <link
      rel="stylesheet"
      href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css"
    />
  </head>
  <body>
    <div id="swagger-ui"></div>
    <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js">
    </script>
    <script>
      SwaggerUIBundle({
        url: "/openapi.json",
        dom_id: "#swagger-ui",
        presets: [
          SwaggerUIBundle.presets.apis,
          SwaggerUIBundle.SwaggerUIStandalonePreset
        ],
        layout: "BaseLayout",
        deepLinking: true
      })
    </script>
  </body>
</html>''';

/// Returns a Shelf [Handler] that serves the Swagger UI HTML.
///
/// ```dart
/// router.get('/docs', swaggerDocsHandler(title: 'My API'));
/// ```
Handler swaggerDocsHandler({required String title}) {
  final html = _swaggerUiHtmlTemplate.replaceFirst('{{title}}', title);

  return (Request request) {
    return Response.ok(
      html,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  };
}
