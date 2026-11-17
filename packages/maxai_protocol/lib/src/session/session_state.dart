/// Состояния жизненного цикла MAX-сессии.
enum SessionState {
  idle,
  initializing,
  ready,
  failed,
  closed,
}
