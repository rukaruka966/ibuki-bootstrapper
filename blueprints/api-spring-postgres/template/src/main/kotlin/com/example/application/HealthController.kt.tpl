package __BASE_PACKAGE__

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RestController

@RestController
class HealthController {
    @GetMapping("/internal/health")
    fun health(): Map<String, String> = mapOf("status" to "ok")
}
