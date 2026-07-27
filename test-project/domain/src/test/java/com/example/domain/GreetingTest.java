package com.example.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class GreetingTest {
  @Test
  void forName_usesProvidedName() {
    assertEquals("Hello, Maxime!", Greeting.forName("Maxime").message());
  }

  @Test
  void forName_defaultsWhenBlank() {
    assertEquals("Hello, world!", Greeting.forName("  ").message());
  }
}
