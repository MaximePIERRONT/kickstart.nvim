package com.example.infrastructure;

import static org.junit.jupiter.api.Assertions.assertEquals;

import com.example.domain.Greeting;
import org.junit.jupiter.api.Test;

class GreetingFacadeImplTest {
  @Test
  void greet_delegatesToDomain() {
    GreetingFacadeImpl facade = new GreetingFacadeImpl();
    Greeting greeting = facade.greet("CI");
    assertEquals("Hello, CI!", greeting.message());
  }
}
