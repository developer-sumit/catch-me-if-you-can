package store

import (
	"context"
	"github.com/soulserve/soulserve/backend/internal/domain"
)

type Store interface {
	CreateUser(context.Context, domain.User) (domain.User, error)
	UserByEmail(context.Context, string) (domain.User, error)
	UserByID(context.Context, string) (domain.User, error)
	CreateWaste(context.Context, domain.WasteLog) (domain.WasteLog, error)
	WasteByID(context.Context, string) (domain.WasteLog, error)
	WasteForKitchen(context.Context, string) ([]domain.WasteLog, error)
	AvailableWaste(context.Context) ([]domain.WasteLog, error)
	CreateClaim(context.Context, string, string) (domain.Claim, error)
	AdvanceClaim(ctx context.Context, claimID, ngoID, target string) (domain.Claim, error)
	ClaimsForNGO(context.Context, string) ([]domain.Claim, error)
	KitchenStats(context.Context, string) (domain.KitchenStats, error)
	NGOStats(context.Context, string) (domain.NGOStats, error)
	History(context.Context, string, int) ([]domain.WasteLog, error)
	Health(context.Context) error
	Close()
}
