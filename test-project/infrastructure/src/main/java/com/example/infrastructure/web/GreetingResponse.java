package com.example.infrastructure.web;

import io.micronaut.serde.annotation.Serdeable;

@Serdeable
public record GreetingResponse(String message) {}
