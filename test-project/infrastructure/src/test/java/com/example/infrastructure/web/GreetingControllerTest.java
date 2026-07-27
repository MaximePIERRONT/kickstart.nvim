package com.example.infrastructure.web;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import io.micronaut.http.HttpRequest;
import io.micronaut.http.client.HttpClient;
import io.micronaut.http.client.annotation.Client;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import jakarta.inject.Inject;
import org.junit.jupiter.api.Test;

@MicronautTest
class GreetingControllerTest {
  @Inject
  @Client("/")
  HttpClient client;

  @Test
  void greet_returnsHelloPayload() {
    GreetingResponse body = client.toBlocking().retrieve(HttpRequest.GET("/greetings?name=Micronaut"), GreetingResponse.class);
    assertEquals("Hello, Micronaut!", body.message());
  }

  @Test
  void application_beanIsWired() {
    assertNotNull(client);
  }
}
