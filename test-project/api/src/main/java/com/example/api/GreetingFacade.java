package com.example.api;

import com.example.domain.Greeting;

public interface GreetingFacade {
  Greeting greet(String name);
}
