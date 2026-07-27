package com.example.infrastructure;

/**
 * Tiny entrypoint used by DAP smoke tests (discoverable main class).
 */
public final class DebugProbe {
  private DebugProbe() {}

  public static int add(int a, int b) {
    return a + b;
  }

  public static void main(String[] args) {
    int result = add(21, 21);
    System.out.println("debug-probe=" + result);
    if (result != 42) {
      throw new IllegalStateException("unexpected result: " + result);
    }
  }
}
