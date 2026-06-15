class CleanRestoresInterrupt {
  void wait500() {
    try { Thread.sleep(500); }
    catch (InterruptedException e) { Thread.currentThread().interrupt(); }
  }
}
