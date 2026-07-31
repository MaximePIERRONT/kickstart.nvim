package com.example.infrastructure.web;

import com.example.api.GreetingFacade;
import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;
import io.micronaut.http.annotation.QueryValue;

@Controller("/greetings")
public class GreetingController {
  private final GreetingFacade greetingFacade;

  public GreetingController(GreetingFacade greetingFacade) {
    this.greetingFacade = greetingFacade;
  }

  @Get
  public GreetingResponse greet(@QueryValue(defaultValue = "world") String name) {
    return new GreetingResponse(greetingFacade.greet(name).message());
  }
}
