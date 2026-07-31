package com.example.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class GreetingNullTest {
  @Test
  void forName_defaultsWhenNull() {
    assertEquals("Hello, world!", Greeting.forName(null).message());
  }
}
