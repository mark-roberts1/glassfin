#include "GlassfinScheme.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QUrl>
#include <QtWebEngineCore/QWebEngineProfile>
#include <QtWebEngineCore/QWebEngineUrlRequestJob>
#include <QtWebEngineCore/QWebEngineUrlScheme>

#define GLASSFIN_RESOURCE_ROOT ":/glassfin"

/////////////////////////////////////////////////////////////////////////////////////////
//
// Extensions are mapped by hand rather than asked of QMimeDatabase.
//
// The front end is loaded as an ES module, and Chromium enforces the MIME type
// on module scripts strictly: anything that is not a JavaScript type is
// refused, and the page comes up blank with one console line to explain it.
// QMimeDatabase answers from the host's shared-mime-info database, which is a
// property of the machine doing the serving — on a stripped container it can
// answer `text/plain` for a .js file. That is not a thing to discover in the
// field.
//
static QByteArray mimeTypeFor(const QString& path)
{
  static const struct { const char* suffix; const char* type; } types[] = {
    { ".html",  "text/html" },
    { ".js",    "text/javascript" },
    { ".css",   "text/css" },
    { ".json",  "application/json" },
    { ".svg",   "image/svg+xml" },
    { ".png",   "image/png" },
    { ".jpg",   "image/jpeg" },
    { ".jpeg",  "image/jpeg" },
    { ".webp",  "image/webp" },
    { ".ico",   "image/x-icon" },
    { ".woff2", "font/woff2" },
    { ".woff",  "font/woff" },
    { ".ttf",   "font/ttf" },
    { ".txt",   "text/plain" },
    { ".map",   "application/json" },
  };

  for (const auto& entry : types)
  {
    if (path.endsWith(QLatin1String(entry.suffix), Qt::CaseInsensitive))
      return QByteArray(entry.type);
  }

  return QByteArrayLiteral("application/octet-stream");
}

/////////////////////////////////////////////////////////////////////////////////////////
void GlassfinSchemeHandler::registerScheme()
{
  QWebEngineUrlScheme scheme(QByteArrayLiteral(GLASSFIN_SCHEME));

  // Host required, no port and no user information — `glassfin://app/…` and
  // nothing else is a valid address.
  scheme.setSyntax(QWebEngineUrlScheme::Syntax::Host);
  scheme.setDefaultPort(QWebEngineUrlScheme::PortUnspecified);
  scheme.setFlags(QWebEngineUrlScheme::SecureScheme |      // trustworthy: Web Storage works
                  QWebEngineUrlScheme::CorsEnabled |       // the page may call the Jellyfin server
                  QWebEngineUrlScheme::FetchApiAllowed);   // …and fetch its own assets

  QWebEngineUrlScheme::registerScheme(scheme);
}

/////////////////////////////////////////////////////////////////////////////////////////
void GlassfinSchemeHandler::install()
{
  // Outlives every page in the profile, which is what the profile expects of a
  // handler it has been given.
  static GlassfinSchemeHandler handler;
  QWebEngineProfile::defaultProfile()->installUrlSchemeHandler(
    QByteArrayLiteral(GLASSFIN_SCHEME), &handler);
}

/////////////////////////////////////////////////////////////////////////////////////////
void GlassfinSchemeHandler::requestStarted(QWebEngineUrlRequestJob* job)
{
  const QUrl url = job->requestUrl();

  if (url.host() != QLatin1String(GLASSFIN_HOST))
  {
    qWarning() << "Glassfin: refusing request for unknown host" << url.host();
    job->fail(QWebEngineUrlRequestJob::UrlNotFound);
    return;
  }

  QString path = url.path();
  if (path.isEmpty() || path == QLatin1String("/"))
    path = QStringLiteral("/index.html");

  // cleanPath resolves any `..` before it is compared, so a request cannot
  // climb out of the front end's own subtree and read the rest of the binary's
  // resources.
  const QString resource = QDir::cleanPath(QStringLiteral(GLASSFIN_RESOURCE_ROOT) + path);
  if (!resource.startsWith(QStringLiteral(GLASSFIN_RESOURCE_ROOT "/")))
  {
    qWarning() << "Glassfin: refusing request outside the front end:" << path;
    job->fail(QWebEngineUrlRequestJob::UrlNotFound);
    return;
  }

  // Parented to the job so the reply owns its lifetime.
  auto* file = new QFile(resource, job);
  if (!file->open(QIODevice::ReadOnly))
  {
    qWarning() << "Glassfin: no such resource" << resource
               << "- was the front end built into this binary?";
    job->fail(QWebEngineUrlRequestJob::UrlNotFound);
    return;
  }

  job->reply(mimeTypeFor(resource), file);
}
