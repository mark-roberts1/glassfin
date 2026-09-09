//
// Created by Tobias Hieta on 07/03/16.
//

#ifndef PLEXMEDIAPLAYER_EVENTFILTER_H
#define PLEXMEDIAPLAYER_EVENTFILTER_H

#include <QObject>
#include <QEvent>
#include <QSet>

class EventFilter : public QObject
{
  Q_OBJECT
public:
  explicit EventFilter(QObject* parent = nullptr) : QObject(parent) {}

protected:
  bool eventFilter(QObject* watched, QEvent* event) override;

private:
  // Which physical keys are currently held, so OS auto-repeat of one key can
  // be swallowed (isAutoRepeat() isn't reliable — QTBUG-57335) without a
  // second key pressed before the first is released — completely normal
  // during real typing — being mistaken for a repeat and dropped too.
  QSet<int> m_keysDown;
};

#endif //PLEXMEDIAPLAYER_EVENTFILTER_H
