.PHONY: up down backend frontend test
up:
	docker compose up --build
down:
	docker compose down
backend:
	cd backend && go run ./cmd/api
frontend:
	cd frontend && flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api
test:
	cd backend && go test ./...
	cd frontend && flutter test

