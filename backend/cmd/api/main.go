package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/joho/godotenv"
	"github.com/soulserve/soulserve/backend/internal/config"
	"github.com/soulserve/soulserve/backend/internal/database"
	"github.com/soulserve/soulserve/backend/internal/httpapi"
	"github.com/soulserve/soulserve/backend/internal/service"
	"github.com/soulserve/soulserve/backend/internal/store/postgres"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	// Existing environment variables take precedence over local development files.
	_ = godotenv.Load("../.env")
	_ = godotenv.Load(".env")
	cfg, err := config.Load()
	if err != nil {
		log.Error("configuration", "error", err)
		os.Exit(1)
	}
	ctx := context.Background()
	if err = database.Migrate(ctx, cfg.DatabaseURL); err != nil {
		log.Error("migration", "error", err)
		os.Exit(1)
	}
	st, err := postgres.New(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Error("database", "error", err)
		os.Exit(1)
	}
	defer st.Close()
	svc := service.New(st, cfg.JWTSecret, cfg.TokenTTL)
	server := &http.Server{Addr: cfg.HTTPAddr, Handler: httpapi.New(svc, log, cfg.AllowedOrigins), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second}
	go func() {
		log.Info("api listening", "address", cfg.HTTPAddr)
		if e := server.ListenAndServe(); e != nil && e != http.ErrServerClosed {
			log.Error("server", "error", e)
			os.Exit(1)
		}
	}()
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = server.Shutdown(shutdown)
}
