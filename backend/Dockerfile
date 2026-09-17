FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -o /api ./cmd/api

FROM alpine:3.21
RUN adduser -D -H app
USER app
COPY --from=build /api /api
EXPOSE 8080
ENTRYPOINT ["/api"]
