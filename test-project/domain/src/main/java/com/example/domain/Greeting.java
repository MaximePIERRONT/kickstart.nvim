package com.example.domain;

public record Greeting(String message) {
  public static Greeting forName(String name) {
    String safe = (name == null || name.isBlank()) ? "world" : name.trim();
    return new Greeting("Hello, " + safe + "!");
  }
}
