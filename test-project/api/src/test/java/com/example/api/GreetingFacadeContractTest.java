package com.example.api;

import static org.junit.jupiter.api.Assertions.assertEquals;

import com.example.domain.Greeting;
import org.junit.jupiter.api.Test;

class GreetingFacadeContractTest {
  @Test
  void facade_returnsDomainGreeting() {
    GreetingFacade facade = Greeting::forName;
    assertEquals("Hello, api!", facade.greet("api").message());
  }
}
