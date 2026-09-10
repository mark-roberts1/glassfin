#include "MpvVideoItem.h"
#include "PlayerComponent.h"
#include <MpvController>
#include <QDebug>

MpvVideoItem::MpvVideoItem(QQuickItem *parent)
    : MpvAbstractItem(parent)
{
    qDebug() << "MpvVideoItem constructed";
    // Critical: Set vo=libmpv for Qt integration
    Q_EMIT setProperty("vo", "libmpv");

#ifdef Q_OS_WIN32
    // Force desktop OpenGL and disable advanced features for compatibility with older GPUs
    Q_EMIT setProperty("gpu-api", "opengl");
    Q_EMIT setProperty("opengl-es", "no");
#endif
}

void MpvVideoItem::setPlayerComponent(PlayerComponent* player)
{
    m_player = player;

    // mpvController() is set synchronously in the constructor, so it is
    // non-null immediately and useless as a readiness check. The real
    // signal that mpv has a render context (created lazily from
    // createFramebufferObject(), the first time the item actually gets
    // painted) is the ready() signal below. Initializing PlayerComponent
    // before that exists means its first setProperty("force-window", true)
    // tries to open the VO with no render context yet, which mpv logs as
    // "No render context set" and silently never retries for that session.
    connect(this, &MpvAbstractItem::ready, this, [this]() {
        if (m_player) {
            m_player->setMpvController(mpvController());
            m_player->initializeMpv();
        }
    });
}
