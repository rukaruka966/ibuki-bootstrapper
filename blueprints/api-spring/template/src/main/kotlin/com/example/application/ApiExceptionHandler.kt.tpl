package com.example.application

import jakarta.servlet.http.HttpServletRequest
import org.springframework.http.HttpStatus
import org.springframework.http.ProblemDetail
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import org.springframework.web.servlet.NoHandlerFoundException

@RestControllerAdvice
class ApiExceptionHandler {
    @ExceptionHandler(NoHandlerFoundException::class)
    fun handleNotFound(
        exception: NoHandlerFoundException,
        request: HttpServletRequest,
    ): ProblemDetail =
        ProblemDetail.forStatusAndDetail(
            HttpStatus.NOT_FOUND,
            "No endpoint is available for ${request.requestURI}.",
        ).apply {
            type = java.net.URI.create("about:blank")
            title = "Not Found"
            instance = java.net.URI.create(request.requestURI)
        }
}
