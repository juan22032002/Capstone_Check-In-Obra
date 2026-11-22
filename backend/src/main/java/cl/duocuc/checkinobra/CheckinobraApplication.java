package cl.duocuc.checkinobra;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
// Purga de las claves de idempotencia vencidas (RegistroIdempotencia).
@EnableScheduling
public class CheckinobraApplication {

	public static void main(String[] args) {
		SpringApplication.run(CheckinobraApplication.class, args);
	}

}
