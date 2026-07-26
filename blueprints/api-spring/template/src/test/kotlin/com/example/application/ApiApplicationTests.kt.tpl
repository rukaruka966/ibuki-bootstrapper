package com.example.application

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.assertEquals
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.mock.web.MockHttpServletRequest
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.setup.MockMvcBuilders
import org.springframework.web.servlet.NoHandlerFoundException

class ApiApplicationTests {
    private val mockMvc: MockMvc =
        MockMvcBuilders
            .standaloneSetup(HealthController())
            .setControllerAdvice(ApiExceptionHandler())
            .build()

    @Test
    fun `health endpoint reports ok`() {
        mockMvc.get("/internal/health")
            .andExpect {
                status { isOk() }
                content { contentTypeCompatibleWith(MediaType.APPLICATION_JSON) }
                jsonPath("$.status") { value("ok") }
            }
    }

    @Test
    fun `unknown route returns RFC 7807 problem details`() {
        val request = MockHttpServletRequest("GET", "/missing")
        val exception = NoHandlerFoundException("GET", "/missing", HttpHeaders.EMPTY)
        val problem = ApiExceptionHandler().handleNotFound(exception, request)

        assertEquals(HttpStatus.NOT_FOUND.value(), problem.status)
        assertEquals("about:blank", problem.type.toString())
        assertEquals("Not Found", problem.title)
        assertEquals("/missing", problem.instance.toString())
    }
}

@SpringBootTest
class ApplicationContextTests {
    @Test
    fun `application context loads`() {
    }
}
