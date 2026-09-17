package database

import (
	"context"
	"embed"
	"fmt"
	"sort"

	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed migrations/*.sql
var files embed.FS

func Migrate(ctx context.Context, databaseURL string) error {
	p, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return err
	}
	defer p.Close()
	entries, err := files.ReadDir("migrations")
	if err != nil {
		return err
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Name() < entries[j].Name() })
	for _, e := range entries {
		b, err := files.ReadFile("migrations/" + e.Name())
		if err != nil {
			return err
		}
		if _, err = p.Exec(ctx, string(b)); err != nil {
			return fmt.Errorf("migration %s: %w", e.Name(), err)
		}
	}
	return nil
}
