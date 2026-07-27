package com.example.infrastructure;

import com.example.api.GreetingFacade;
import com.example.domain.Greeting;
import jakarta.inject.Singleton;

@Singleton
public class GreetingFacadeImpl implements GreetingFacade {
  @Override
  public Greeting greet(String name) {
    return Greeting.forName(name);
  }
}
