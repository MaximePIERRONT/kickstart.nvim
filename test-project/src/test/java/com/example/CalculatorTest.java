package com.example;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

@DisplayName("Calculator")
class CalculatorTest {

    private Calculator calculator;

    @BeforeEach
    void setUp() {
        calculator = new Calculator();
    }

    @Nested
    @DisplayName("add")
    class AddTest {

        @Test
        @DisplayName("should add two positive numbers")
        void shouldAddTwoPositiveNumbers() {
            assertEquals(5, calculator.add(2, 3));
        }

        @Test
        @DisplayName("should add negative numbers")
        void shouldAddNegativeNumbers() {
            assertEquals(-5, calculator.add(-2, -3));
        }

        @Test
        @DisplayName("should add zero")
        void shouldAddZero() {
            assertEquals(3, calculator.add(3, 0));
        }
    }

    @Nested
    @DisplayName("subtract")
    class SubtractTest {

        @Test
        @DisplayName("should subtract two numbers")
        void shouldSubtractTwoNumbers() {
            assertEquals(1, calculator.subtract(3, 2));
        }
    }

    @Nested
    @DisplayName("multiply")
    class MultiplyTest {

        @Test
        @DisplayName("should multiply two numbers")
        void shouldMultiplyTwoNumbers() {
            assertEquals(6, calculator.multiply(2, 3));
        }

        @Test
        @DisplayName("should multiply by zero")
        void shouldMultiplyByZero() {
            assertEquals(0, calculator.multiply(5, 0));
        }
    }

    @Nested
    @DisplayName("divide")
    class DivideTest {

        @Test
        @DisplayName("should divide two numbers")
        void shouldDivideTwoNumbers() {
            assertEquals(2, calculator.divide(6, 3));
        }

        @Test
        @DisplayName("should throw on divide by zero")
        void shouldThrowOnDivideByZero() {
            assertThrows(ArithmeticException.class, () -> calculator.divide(1, 0));
        }
    }
}
