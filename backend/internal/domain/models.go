package domain

import "time"

type Role string

const (
	RoleKitchen Role = "kitchen"
	RoleNGO     Role = "ngo"
)

type User struct {
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	Role         Role      `json:"role"`
	Organization string    `json:"organization"`
	Phone        string    `json:"phone"`
	Address      string    `json:"address"`
	Latitude     *float64  `json:"latitude"`
	Longitude    *float64  `json:"longitude"`
	CreatedAt    time.Time `json:"createdAt"`
}

type WasteLog struct {
	ID         string    `json:"id"`
	KitchenID  string    `json:"kitchenId"`
	FoodType   string    `json:"foodType"`
	Quantity   float64   `json:"quantity"`
	Unit       string    `json:"unit"`
	Status     string    `json:"status"`
	ClaimedBy  *string   `json:"claimedBy,omitempty"`
	Notes      string    `json:"notes"`
	LogDate    time.Time `json:"logDate"`
	CreatedAt  time.Time `json:"createdAt"`
	Kitchen    *User     `json:"kitchen,omitempty"`
	Claimer    *User     `json:"claimer,omitempty"`
	DistanceKM *float64  `json:"distance,omitempty"`
}

// Claim stages, in the order a delivery moves through them.
const (
	ClaimClaimed        = "claimed"
	ClaimPickedUp       = "picked_up"
	ClaimOutForDelivery = "out_for_delivery"
	ClaimCompleted      = "completed"
	ClaimCancelled      = "cancelled"
)

// ClaimStages is the delivery progression. Order is meaningful: a claim may
// only move forward through it.
var ClaimStages = []string{ClaimClaimed, ClaimPickedUp, ClaimOutForDelivery, ClaimCompleted}

// ClaimStageIndex reports the position of a stage in [ClaimStages], or -1 when
// the value is not part of the progression (an unknown stage, or cancelled).
func ClaimStageIndex(stage string) int {
	for i, s := range ClaimStages {
		if s == stage {
			return i
		}
	}
	return -1
}

// ClaimStagesBefore lists the stages a claim may legally advance from in order
// to reach target. Skipping ahead is allowed: a courier who forgets to tap
// "picked up" should still be able to record the delivery.
func ClaimStagesBefore(target string) []string {
	i := ClaimStageIndex(target)
	if i <= 0 {
		return nil
	}
	return ClaimStages[:i]
}

type Claim struct {
	ID               string     `json:"id"`
	WasteLogID       string     `json:"wasteLogId"`
	NGOID            string     `json:"ngoId"`
	KitchenID        string     `json:"kitchenId"`
	Status           string     `json:"status"`
	ClaimedAt        time.Time  `json:"claimedAt"`
	PickedUpAt       *time.Time `json:"pickedUpAt,omitempty"`
	OutForDeliveryAt *time.Time `json:"outForDeliveryAt,omitempty"`
	CompletedAt      *time.Time `json:"completedAt,omitempty"`
	WasteLog         *WasteLog  `json:"wasteLog,omitempty"`
	Kitchen          *User      `json:"kitchen,omitempty"`
	NGO              *User      `json:"ngo,omitempty"`
}

type KitchenStats struct {
	TotalLogged           int         `json:"totalLogged"`
	TotalQuantity         float64     `json:"totalQuantity"`
	TotalClaimed          int         `json:"totalClaimed"`
	TotalCompleted        int         `json:"totalCompleted"`
	TotalPending          int         `json:"totalPending"`
	RedistributedQuantity float64     `json:"redistributedQuantity"`
	ByType                []FoodTotal `json:"byType"`
}
type FoodTotal struct {
	FoodType string  `json:"foodType"`
	Total    float64 `json:"total"`
}
type NGOStats struct {
	TotalClaimed       int     `json:"totalClaimed"`
	TotalCompleted     int     `json:"totalCompleted"`
	TotalQuantitySaved float64 `json:"totalQuantitySaved"`
}
