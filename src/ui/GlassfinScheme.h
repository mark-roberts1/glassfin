#ifndef GLASSFINSCHEME_H
#define GLASSFINSCHEME_H

#include <QtWebEngineCore/QWebEngineUrlSchemeHandler>

//
// The front end is served on its own URL scheme rather than from qrc:///.
//
// A qrc URL has no host, so Chromium gives the page an opaque origin, and an
// opaque origin has no Web Storage: localStorage throws, which in this
// application means no saved server, no saved sign-in and no saved
// preferences. `glassfin://app/` is a real origin, and registering it as a
// secure scheme also makes it a trustworthy context — the same footing a page
// served over HTTPS gets.
//
// The bytes still come out of the Qt resource system; only the address the
// page sees is different.
//

#define GLASSFIN_SCHEME "glassfin"
#define GLASSFIN_HOST "app"
#define GLASSFIN_URL "glassfin://app/index.html"

/** Serves `glassfin://app/<path>` out of `:/glassfin/<path>`. */
class GlassfinSchemeHandler : public QWebEngineUrlSchemeHandler
{
  Q_OBJECT

public:
  explicit GlassfinSchemeHandler(QObject* parent = nullptr) : QWebEngineUrlSchemeHandler(parent) {}

  void requestStarted(QWebEngineUrlRequestJob* job) override;

  /**
   * Declares the scheme. Must run before QtWebEngineQuick::initialize(), which
   * is when Chromium takes its copy of the scheme registry; afterwards it is
   * too late and the scheme silently behaves like an unknown one.
   */
  static void registerScheme();

  /** Installs the handler on the default profile. Needs a QApplication first. */
  static void install();
};

#endif // GLASSFINSCHEME_H
